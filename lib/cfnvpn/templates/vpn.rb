require 'cfndsl'
require 'cfnvpn/templates/helper'
require 'cfnvpn/templates/lambdas'

module CfnVpn
  module Templates
    class Vpn < CfnDsl::CloudFormationTemplate

      def initialize
        super
      end

      def render(name, config)
        Description "cfnvpn #{name} AWS Client-VPN"
        Parameter(:AssociateSubnets) {
          Type 'String'
          Default 'true'
          AllowedValues ['true', 'false']
          Description 'Toggle to false to disassociate all Client VPN subnet associations'
        }

        Condition(:EnableSubnetAssociation, FnEquals(Ref(:AssociateSubnets), 'true'))

        Logs_LogGroup(:ClientVpnLogGroup) {
          LogGroupName FnSub("#{name}-ClientVpn")
          RetentionInDays 30
        }

        EC2_ClientVpnEndpoint(:ClientVpnEndpoint) {
          Description FnSub("cfnvpn #{name} AWS Client-VPN")
          AuthenticationOptions([
          if config[:type] == 'federated'
            {
              FederatedAuthentication: {
                SAMLProviderArn: config[:saml_arn],
                SelfServiceSAMLProviderArn: config[:saml_arn]
              },
              Type: 'federated-authentication'
            }
          elsif config[:type] == 'active-directory'
            {
              ActiveDirectory: {
                DirectoryId: config[:directory_id]
              },
              Type: 'directory-service-authentication'
            }
          else
            {
              MutualAuthentication: {
                ClientRootCertificateChainArn: config[:client_cert_arn]
              },
              Type: 'certificate-authentication'
            }
          end
          ])
          ServerCertificateArn config[:server_cert_arn]
          ClientCidrBlock config[:cidr]
          ConnectionLogOptions({
            CloudwatchLogGroup: Ref(:ClientVpnLogGroup),
            Enabled: true
          })
          DnsServers config[:dns_servers].any? ? config[:dns_servers] : Ref('AWS::NoValue')
          TagSpecifications([{
            ResourceType: "client-vpn-endpoint",
            Tags: [
              { Key: 'Name', Value: name }
            ]
          }])
          TransportProtocol config[:protocol]
          SplitTunnel config[:split_tunnel]
        }

        network_assoc_dependson = []
        config[:subnet_ids].each_with_index do |subnet, index|
          suffix = index == 0 ? "" : "For#{subnet.resource_safe}"

          EC2_ClientVpnTargetNetworkAssociation(:"ClientVpnTargetNetworkAssociation#{suffix}") {
            Condition(:EnableSubnetAssociation)
            ClientVpnEndpointId Ref(:ClientVpnEndpoint)
            SubnetId subnet
          }

          network_assoc_dependson << "ClientVpnTargetNetworkAssociation#{suffix}"
        end

        if config[:default_groups].any?
          config[:default_groups].each do |group|
            EC2_ClientVpnAuthorizationRule(:"TargetNetworkAuthorizationRule#{group.resource_safe}"[0..255]) {
              Condition(:EnableSubnetAssociation)
              DependsOn network_assoc_dependson if network_assoc_dependson.any?
              Description FnSub("#{name} client-vpn auth rule for subnet association")
              AccessGroupId group
              ClientVpnEndpointId Ref(:ClientVpnEndpoint)
              TargetNetworkCidr CfnVpn::Templates::Helper.get_auth_cidr(config[:region], config[:subnet_ids].first)
            }
          end
        else
          EC2_ClientVpnAuthorizationRule(:"TargetNetworkAuthorizationRule") {
            Condition(:EnableSubnetAssociation)
            DependsOn network_assoc_dependson if network_assoc_dependson.any?
            Description FnSub("#{name} client-vpn auth rule for subnet association")
            AuthorizeAllGroups true
            ClientVpnEndpointId Ref(:ClientVpnEndpoint)
            TargetNetworkCidr CfnVpn::Templates::Helper.get_auth_cidr(config[:region], config[:subnet_ids].first)
          }
        end

        if !config[:internet_route].nil?
          EC2_ClientVpnRoute(:RouteToInternet) {
            Condition(:EnableSubnetAssociation)
            DependsOn network_assoc_dependson if network_assoc_dependson.any?
            Description "Route to the internet through subnet #{config[:internet_route]}"
            ClientVpnEndpointId Ref(:ClientVpnEndpoint)
            DestinationCidrBlock '0.0.0.0/0'
            TargetVpcSubnetId config[:internet_route]
          }
        
          EC2_ClientVpnAuthorizationRule(:RouteToInternetAuthorizationRule) {
            Condition(:EnableSubnetAssociation)
            DependsOn network_assoc_dependson if network_assoc_dependson.any?
            Description "Internet route authorization from subnet #{config[:internet_route]}"
            AuthorizeAllGroups true
            ClientVpnEndpointId Ref(:ClientVpnEndpoint)
            TargetNetworkCidr '0.0.0.0/0'
          }

          output(:InternetRoute, config[:internet_route])
        end

        dns_routes = config[:routes].select {|route| route.has_key?(:dns)}
        cidr_routes = config[:routes].select {|route| route.has_key?(:cidr)}

        if dns_routes.any?
          auto_route_populator(name, config[:bucket])

          dns_routes.each do |route|
            input = { 
              Record: route[:dns],
              ClientVpnEndpointId: "${ClientVpnEndpoint}",
              TargetSubnet: route[:subnet],
              Description: route[:desc]
            }
            
            if route[:groups].any?
              input[:Groups] = route[:groups]
            end

            Events_Rule(:"CfnVpnAutoRoutePopulatorEvent#{route[:dns].resource_safe}"[0..255]) {
              State 'ENABLED'
              Description "cfnvpn auto route populator schedule for #{route[:dns]}"
              ScheduleExpression "rate(5 minutes)"
              Targets([
                { 
                  Arn: FnGetAtt(:CfnVpnAutoRoutePopulator, :Arn),
                  Id: "cfnvpnautoroutepopulator#{route[:dns].event_id_safe}",
                  Input: FnSub(input.to_json)
                }
              ])
            }
          end
        end

        if cidr_routes.any?
          cidr_routes.each do |route|
            EC2_ClientVpnRoute(:"#{route[:cidr].resource_safe}VpnRoute") {
              Description "cfnvpn static route for #{route[:cidr]}. #{route[:desc]}".strip
              ClientVpnEndpointId Ref(:ClientVpnEndpoint)
              DestinationCidrBlock route[:cidr]
              TargetVpcSubnetId route[:subnet]
            }

            if route[:groups].any?
              route[:groups].each do |group|
                EC2_ClientVpnAuthorizationRule(:"#{route[:cidr].resource_safe}AuthorizationRule#{group.resource_safe}"[0..255]) {
                  Description "cfnvpn static authorization rule for group #{group} to route #{route[:cidr]}. #{route[:desc]}".strip
                  AccessGroupId group
                  ClientVpnEndpointId Ref(:ClientVpnEndpoint)
                  TargetNetworkCidr route[:cidr]
                }
              end
            else
              EC2_ClientVpnAuthorizationRule(:"#{route[:cidr].resource_safe}AllowAllAuthorizationRule") {
                Description "cfnvpn static allow all authorization rule to route #{route[:cidr]}. #{route[:desc]}".strip
                AuthorizeAllGroups true
                ClientVpnEndpointId Ref(:ClientVpnEndpoint)
                TargetNetworkCidr route[:cidr]
              }
            end
          end
        end
        
        SSM_Parameter(:CfnVpnConfig) {
          Description "#{name} cfnvpn config"
          Name "/cfnvpn/config/#{name}"
          Tier 'Standard'
          Type 'String'
          Value config.to_json
          Tags({
            Name: "#{name}-cfnvpn-config",
            Environment: 'cfnvpn'
          })
        }

        if config[:start] || config[:stop]
          scheduler(name, config[:start], config[:stop], config[:bucket])
          output(:Start, config[:start]) if config[:start]
          output(:Stop, config[:stop]) if config[:stop]
        end

        output(:ServerCertArn, config[:server_cert_arn])
        output(:Cidr, config[:cidr])
        output(:DnsServers, config.fetch(:dns_servers, []).join(','))
        output(:SubnetIds, config[:subnet_ids].join(','))
        output(:SplitTunnel, config[:split_tunnel])
        output(:Protocol, config[:protocol])
        output(:Type, config[:type])

        if config[:type] == 'federated'
          output(:SamlArn, config[:saml_arn])
        elsif config[:type] == 'active-directory'
          output(:DirectoryId, config[:directory_id])
        else
          output(:ClientCertArn, config[:client_cert_arn])
        end
      end

      def output(name, value)
        Output(name) { Value value }
      end

      def auto_route_populator(name, bucket)
        IAM_Role(:CfnVpnAutoRoutePopulatorRole) {
          AssumeRolePolicyDocument({
            Version: '2012-10-17',
            Statement: [{
              Effect: 'Allow',
              Principal: { Service: [ 'lambda.amazonaws.com' ] },
              Action: [ 'sts:AssumeRole' ]
            }]
          })
          Path '/cfnvpn/'
          Policies([
            {
              PolicyName: 'client-vpn',
              PolicyDocument: {
                Version: '2012-10-17',
                Statement: [{
                  Effect: 'Allow',
                  Action: [ 
                    'ec2:AuthorizeClientVpnIngress',
                    'ec2:RevokeClientVpnIngress',
                    'ec2:DescribeClientVpnAuthorizationRules',
                    'ec2:DescribeClientVpnEndpoints',
                    'ec2:DescribeClientVpnRoutes',
                    'ec2:CreateClientVpnRoute',
                    'ec2:DeleteClientVpnRoute'
                  ],
                  Resource: '*'
                }]
              }
            },
            {
              PolicyName: 'logging',
              PolicyDocument: {
                Version: '2012-10-17',
                Statement: [{
                  Effect: 'Allow',
                  Action: [
                    'logs:DescribeLogGroups',
                    'logs:CreateLogGroup',
                    'logs:CreateLogStream',
                    'logs:DescribeLogStreams',
                    'logs:PutLogEvents'
                  ],
                  Resource: '*'
                }]
              }
            }
          ])
          Tags([
            { Key: 'Name', Value: "#{name}-cfnvpn-auto-route-populator-role" },
            { Key: 'Environment', Value: 'cfnvpn' }
          ])
        }

        s3_key = CfnVpn::Templates::Lambdas.package_lambda(name: name, bucket: bucket, func: 'auto_route_populator', files: ['app.py'])
        
        Lambda_Function(:CfnVpnAutoRoutePopulator) {
          Runtime 'python3.8'
          Role FnGetAtt(:CfnVpnAutoRoutePopulatorRole, :Arn)
          MemorySize '128'
          Handler 'app.handler'
          Timeout 60
          Code({
            S3Bucket: bucket,
            S3Key: s3_key
          })
          Tags([
            { Key: 'Name', Value: "#{name}-cfnvpn-auto-route-populator" },
            { Key: 'Environment', Value: 'cfnvpn' }
          ])
        }

        Logs_LogGroup(:CfnVpnAutoRoutePopulatorLogGroup) {
          LogGroupName FnSub("/aws/lambda/${CfnVpnAutoRoutePopulator}")
          RetentionInDays 30
        }

        Lambda_Permission(:CfnVpnAutoRoutePopulatorFunctionPermissions) {
          FunctionName Ref(:CfnVpnAutoRoutePopulator)
          Action 'lambda:InvokeFunction'
          Principal 'events.amazonaws.com'
        }
      end

      def scheduler(name, start, stop, bucket)
        IAM_Role(:ClientVpnSchedulerRole) {
          AssumeRolePolicyDocument({
            Version: '2012-10-17',
            Statement: [{
              Effect: 'Allow',
              Principal: { Service: [ 'lambda.amazonaws.com' ] },
              Action: [ 'sts:AssumeRole' ]
            }]
          })
          Path '/cfnvpn/'
          Policies([
            {
              PolicyName: 'cloudformation',
              PolicyDocument: {
                Version: '2012-10-17',
                Statement: [{
                  Effect: 'Allow',
                  Action: [
                    'cloudformation:UpdateStack'
                  ],
                  Resource: FnSub("arn:aws:cloudformation:${AWS::Region}:${AWS::AccountId}:stack/#{name}-cfnvpn/*")
                }]
              }
            },
            {
              PolicyName: 'client-vpn',
              PolicyDocument: {
                Version: '2012-10-17',
                Statement: [{
                  Effect: 'Allow',
                  Action: [ 
                    'ec2:AssociateClientVpnTargetNetwork',
                    'ec2:DisassociateClientVpnTargetNetwork',
                    'ec2:DescribeClientVpnTargetNetworks',
                    'ec2:AuthorizeClientVpnIngress',
                    'ec2:RevokeClientVpnIngress',
                    'ec2:DescribeClientVpnAuthorizationRules',
                    'ec2:DescribeClientVpnEndpoints',
                    'ec2:DescribeClientVpnConnections',
                    'ec2:TerminateClientVpnConnections'
                  ],
                  Resource: '*'
                }]
              }
            },
            {
              PolicyName: 'logging',
              PolicyDocument: {
                Version: '2012-10-17',
                Statement: [{
                  Effect: 'Allow',
                  Action: [
                    'logs:DescribeLogGroups',
                    'logs:CreateLogGroup',
                    'logs:CreateLogStream',
                    'logs:DescribeLogStreams',
                    'logs:PutLogEvents'
                  ],
                  Resource: '*'
                }]
              }
            }
          ])
          Tags([
            { Key: 'Name', Value: "#{name}-cfnvpn-scheduler-role" },
            { Key: 'Environment', Value: 'cfnvpn' }
          ])
        }

        s3_key = CfnVpn::Templates::Lambdas.package_lambda(name: name, bucket: bucket, func: 'scheduler', files: ['app.py'])

        Lambda_Function(:ClientVpnSchedulerFunction) {
          Runtime 'python3.8'
          Role FnGetAtt(:ClientVpnSchedulerRole, :Arn)
          MemorySize '128'
          Handler 'app.handler'
          Timeout 60
          Code({
            S3Bucket: bucket,
            S3Key: s3_key
          })
          Tags([
            { Key: 'Name', Value: "#{name}-cfnvpn-scheduler-function" },
            { Key: 'Environment', Value: 'cfnvpn' }
          ])
        }

        Logs_LogGroup(:ClientVpnSchedulerLogGroup) {
          LogGroupName FnSub("/aws/lambda/${ClientVpnSchedulerFunction}")
          RetentionInDays 30
        }

        Lambda_Permission(:ClientVpnSchedulerFunctionPermissions) {
          FunctionName Ref(:ClientVpnSchedulerFunction)
          Action 'lambda:InvokeFunction'
          Principal 'events.amazonaws.com'
        }

        if start
          Events_Rule(:ClientVpnSchedulerStart) {
            State 'ENABLED'
            Description "cfnvpn start schedule"
            ScheduleExpression "cron(#{start})"
            Targets([
              { 
                Arn: FnGetAtt(:ClientVpnSchedulerFunction, :Arn),
                Id: 'cfnvpnschedulerstart',
                Input: FnSub({ StackName: "#{name}-cfnvpn", AssociateSubnets: 'true', ClientVpnEndpointId: "${ClientVpnEndpoint}" }.to_json)
              }
            ])
          }
        end

        if stop
          Events_Rule(:ClientVpnSchedulerStop) {
            State 'ENABLED'
            Description "cfnvpn stop schedule"
            ScheduleExpression "cron(#{stop})"
            Targets([
              { 
                Arn: FnGetAtt(:ClientVpnSchedulerFunction, :Arn),
                Id: 'cfnvpnschedulerstop',
                Input: FnSub({ StackName: "#{name}-cfnvpn", AssociateSubnets: 'false', ClientVpnEndpointId: "${ClientVpnEndpoint}" }.to_json)
              }
            ])
          }
        end

      end

    end
  end
end