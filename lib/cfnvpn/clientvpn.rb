require 'aws-sdk-ec2'
require 'cfnvpn/log'

module CfnVpn
  class ClientVpn
    include CfnVpn::Log

    def initialize(name,region)
      @client = Aws::EC2::Client.new(region: region)
      @name = name
    end

    def get_endpoint()
      resp = @client.describe_client_vpn_endpoints({
        filters: [{ name: "tag:cfnvpn:name", values: [@name] }]
      })
      if resp.client_vpn_endpoints.empty?
        Log.logger.error "unable to find endpoint with tag Key: cfnvpn:name with Value: #{@name}"
        raise "Unable to find client vpn"
      end
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
