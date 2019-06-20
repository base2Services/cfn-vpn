require 'aws-sdk-ec2'

module CfnVpn
  class ClientVpn

    def initialize(name,region)
      @client = Aws::EC2::Client.new(region: region)
      @name = name
    end

    def get_endpoint()
      resp = @client.describe_client_vpn_endpoints({
        filters: [{ name: "tag:cfnvpn:name", values: [@name] }]
      })
      resp.client_vpn_endpoints.first
    end

    def get_endpoint_id()
      return get_endpoint().client_vpn_endpoint_id
    end

    def get_config(endpoint_id)
      resp = @client.export_client_vpn_client_configuration({
        client_vpn_endpoint_id: endpoint_id
      })
      return resp.client_configuration
    end

  end
end
