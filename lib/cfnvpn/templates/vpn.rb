require 'cfndsl'

module CfnVpn
  module Templates
    class Vpn < CfnDsl::CloudFormationTemplate

      def initialize
        super
      end

      def render(name, config)
        Description "cfnvpn #{name} AWS Client-VPN"

        Logs_LogGroup(:ClientVpnLogGroup) {
          LogGroupName FnSub("#{name}-ClientVpn")
          RetentionInDays 30
        }

        EC2_ClientVpnEndpoint(:ClientVpnEndpoint) {
          Description FnSub("cfnvpn #{name} AWS Client-VPN")
          AuthenticationOptions([
            {
              MutualAuthentication: {
                ClientRootCertificateChainArn: config[:client_cert_arn]
              },
              Type: 'certificate-authentication'
            }
          ])
          ClientCidrBlock config[:cidr]
          ConnectionLogOptions({
            CloudwatchLogGroup: Ref(:ClientVpnLogGroup),
            Enabled: true
          })
          ServerCertificateArn config[:server_cert_arn]
          DnsServers config[:dns_servers] if config[:dns_servers]
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
          suffix = "For#{subnet.gsub(/[^a-zA-Z0-9]/, "").capitalize}"

          EC2_ClientVpnTargetNetworkAssociation(:"ClientVpnTargetNetworkAssociation#{suffix}") {
            ClientVpnEndpointId Ref(:ClientVpnEndpoint)
            SubnetId subnet
          }

          if config[:internet_route] == true
            EC2_ClientVpnRoute(:"RouteToInternet#{suffix}") {
              DependsOn "ClientVpnTargetNetworkAssociation#{suffix}"
              Description "#{name} client-vpn route to the internet for subnet association"
              ClientVpnEndpointId Ref(:ClientVpnEndpoint)
              DestinationCidrBlock '0.0.0.0/0'
              TargetVpcSubnetId subnet
            }
          
            EC2_ClientVpnAuthorizationRule(:"RouteToInternetAuthorizationRule#{suffix}") {
              DependsOn "ClientVpnTargetNetworkAssociation#{suffix}"
              Description "#{name} client-vpn route to the internet"
              AuthorizeAllGroups true
              ClientVpnEndpointId Ref(:ClientVpnEndpoint)
              TargetNetworkCidr '0.0.0.0/0'
            }
          end
        end

        output(:ClientCertArn, config[:client_cert_arn])
        output(:ServerCertArn, config[:server_cert_arn])
        output(:Cidr, config[:cidr])
        output(:DnsServers, config.fetch(:dns_servers, []).join(','))
        output(:SubnetIds, config[:subnet_ids].join(','))
        output(:SplitTunnel, config[:split_tunnel])
        output(:InternetRoute, config[:internet_route])
        output(:Protocol, config[:protocol])
      end

      def output(name, value)
        Output(name) { Value value }
      end
    end
  end
end