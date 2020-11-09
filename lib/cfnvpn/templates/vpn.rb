require 'cfndsl'
require 'cfnvpn/templates/helper'

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
                SAMLProviderArn: config[:federated],
                SelfServiceSAMLProviderArn: config[:saml_arn]
              },
              Type: 'federated-authentication'
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
          DnsServers config[:dns_servers] if config.fetch(:dns_servers, []).any?
          TagSpecifications([{
            ResourceType: "client-vpn-endpoint",
            Tags: [
              { Key: 'Name', Value: name },
              { Key: 'Environment', Value: name }
            ]
          }])
          TransportProtocol config[:protocol]
          SplitTunnel config[:split_tunnel]
        }

        config[:subnet_ids].each do |subnet|
          suffix = "For#{subnet.resource_safe}"

          EC2_ClientVpnTargetNetworkAssociation(:"ClientVpnTargetNetworkAssociation#{suffix}") {
            Condition(:EnableSubnetAssociation)
            ClientVpnEndpointId Ref(:ClientVpnEndpoint)
            SubnetId subnet
          }

          EC2_ClientVpnAuthorizationRule(:"RouteToInternetAuthorizationRule#{suffix}") {
            Condition(:EnableSubnetAssociation)
            DependsOn "ClientVpnTargetNetworkAssociation#{suffix}"
            Description FnSub("#{name} client-vpn auth rule for subnet association ${ClientVpnTargetNetworkAssociation#{suffix}}")
            AuthorizeAllGroups true
            ClientVpnEndpointId Ref(:ClientVpnEndpoint)
            TargetNetworkCidr CfnVpn::Templates::Helper.get_auth_cidr(config[:region], subnet)
          }
        end

        if config[:subnet_ids].include? config[:internet_route]
          suffix = "For#{config[:internet_route].resource_safe}"

          EC2_ClientVpnRoute(:RouteToInternet) {
            DependsOn "ClientVpnTargetNetworkAssociation#{suffix}"
            Description "#{name} client-vpn route to the internet through subnet #{config[:internet_route_subnet]}"
            ClientVpnEndpointId Ref(:ClientVpnEndpoint)
            DestinationCidrBlock '0.0.0.0/0'
            TargetVpcSubnetId config[:internet_route]
          }
        
          EC2_ClientVpnAuthorizationRule(:RouteToInternetAuthorizationRule) {
            DependsOn "ClientVpnTargetNetworkAssociation#{suffix}"
            Description "#{name} client-vpn auth rule for internet traffic through subnet #{config[:internet_route_subnet]}"
            AuthorizeAllGroups true
            ClientVpnEndpointId Ref(:ClientVpnEndpoint)
            TargetNetworkCidr '0.0.0.0/0'
          }

          output(:InternetRoute, config[:internet_route])
        end

        config[:routes].each do |route|
          suffix = "For#{route[:subnet].resource_safe}"

          EC2_ClientVpnRoute(:"#{route[:cidr].resource_safe}VpnRoute") {
            DependsOn "ClientVpnTargetNetworkAssociation#{suffix}"
            Description route[:desc]
            ClientVpnEndpointId Ref(:ClientVpnEndpoint)
            DestinationCidrBlock route[:cidr]
            TargetVpcSubnetId route[:subnet]
          }

          if route[:groups].any?
            route[:groups].each do |group|
              EC2_ClientVpnAuthorizationRule(:"#{route[:cidr].resource_safe}AuthorizationRule#{group.resource_safe}") {
                DependsOn "ClientVpnTargetNetworkAssociation#{suffix}"
                Description route[:desc]
                AccessGroupId group
                ClientVpnEndpointId Ref(:ClientVpnEndpoint)
                TargetNetworkCidr route[:cidr]
              }
            end
          else
            EC2_ClientVpnAuthorizationRule(:"#{route[:cidr].resource_safe}AllowAllAuthorizationRule") {
              DependsOn "ClientVpnTargetNetworkAssociation#{suffix}"
              Description route[:desc]
              AuthorizeAllGroups true
              ClientVpnEndpointId Ref(:ClientVpnEndpoint)
              TargetNetworkCidr route[:cidr]
            }
          end
        end
        
        SSM_Parameter(:CfnVpnConfig) {
          Description "#{name} cfnvpn config"
          Name "/cfnvpn/config/#{name}"
          Tier 'Standard'
          Type 'String'
          Value config.to_json
          Tags({
            Name:  "#{name}-cfnvpn-config",
            Environment: 'cfnvpn'
          })
        }

        if config[:start] || config[:stop]
          scheduler(name, config[:start], config[:stop])
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
        else
          output(:ClientCertArn, config[:client_cert_arn])
        end
      end

      def output(name, value)
        Output(name) { Value value }
      end

      def federated_vpn()
        EC2_ClientVpnEndpoint(:ClientVpnEndpoint) {
          Description FnSub("cfnvpn #{name} AWS Client-VPN")
          
          ClientCidrBlock config[:cidr]
          ConnectionLogOptions({
            CloudwatchLogGroup: Ref(:ClientVpnLogGroup),
            Enabled: true
          })
          DnsServers config[:dns_servers] if config.fetch(:dns_servers, []).any?
          TagSpecifications([{
            ResourceType: "client-vpn-endpoint",
            Tags: [
              { Key: 'Name', Value: name },
              { Key: 'Environment', Value: name }
            ]
          }])
          TransportProtocol config[:protocol]
          SplitTunnel config[:split_tunnel]
        }
      end

      def scheduler(name, start, stop)
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

        Lambda_Function(:ClientVpnSchedulerFunction) {
          Runtime 'python3.7'
          Role FnGetAtt(:ClientVpnSchedulerRole, :Arn)
          MemorySize '128'
          Handler 'index.handler'
          Code({
            ZipFile: <<~EOS
            import boto3

            def handler(event, context):

              print(f"updating cfn-vpn stack {event['StackName']} parameter AssociateSubnets with value {event['AssociateSubnets']}")

              if event['AssociateSubnets'] == 'false':
                print(f"terminating current vpn sessions to {event['ClientVpnEndpointId']}")
                ec2 = boto3.client('ec2')
                resp = ec2.describe_client_vpn_connections(ClientVpnEndpointId=event['ClientVpnEndpointId'])
                for conn in resp['Connections']:
                  if conn['Status']['Code'] == 'active':
                    ec2.terminate_client_vpn_connections(
                      ClientVpnEndpointId=event['ClientVpnEndpointId'],
                      ConnectionId=conn['ConnectionId']
                    )
                    print(f"terminated session {conn['ConnectionId']}")

              client = boto3.client('cloudformation')
              print(client.update_stack(
                StackName=event['StackName'],
                UsePreviousTemplate=True,
                Capabilities=['CAPABILITY_IAM'],
                Parameters=[
                  {
                    'ParameterKey': 'AssociateSubnets',
                    'ParameterValue': event['AssociateSubnets']
                  }
                ]
              ))

              return 'OK'
            EOS
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