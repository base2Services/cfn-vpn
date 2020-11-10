require 'aws-sdk-ec2'
require 'cfnvpn/log'
require 'netaddr'

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
      if resp.client_vpn_endpoints.empty?
        CfnVpn::Log.logger.error "unable to find endpoint with tag Key: cfnvpn:name with Value: #{@name}"
        raise "Unable to find client vpn"
      end
      return resp.client_vpn_endpoints.first
    end

    def get_endpoint_id()
      return get_endpoint().client_vpn_endpoint_id
    end

    def get_dns_servers()
      return get_endpoint().dns_servers
    end

    def get_config(endpoint_id)
      resp = @client.export_client_vpn_client_configuration({
        client_vpn_endpoint_id: endpoint_id
      })
      return resp.client_configuration
    end

    def get_rekove_list(endpoint_id)
      resp = @client.export_client_vpn_client_certificate_revocation_list({
        client_vpn_endpoint_id: endpoint_id
      })
      return resp.certificate_revocation_list
    end

    def put_revoke_list(endpoint_id,revoke_list)
      list = File.read(revoke_list)
      @client.import_client_vpn_client_certificate_revocation_list({
        client_vpn_endpoint_id: endpoint_id,
        certificate_revocation_list: list
      })
    end

    def get_sessions(endpoint_id)
      params = {
        client_vpn_endpoint_id: endpoint_id,
        max_results: 20
      }
      resp = @client.describe_client_vpn_connections(params)
      return resp.connections
    end

    def kill_session(endpoint_id, connection_id)
      @client.terminate_client_vpn_connections({
        client_vpn_endpoint_id: endpoint_id,
        connection_id: connection_id
      })
    end

    def get_routes()
      endpoint_id = get_endpoint_id()
      resp = @client.describe_client_vpn_routes({
        client_vpn_endpoint_id: endpoint_id,
        max_results: 20
      })
      return resp.routes
    end

    def get_groups_for_route(endpoint, cidr)
      auth_resp = @client.describe_client_vpn_authorization_rules({
        client_vpn_endpoint_id: endpoint,
        filters: [
          {
            name: 'destination-cidr',
            values: [cidr]
          }
        ]
      })
      return auth_resp.authorization_rules.map {|rule| rule.group_id }
    end

    def get_associations(endpoint)
      associations = []
      resp = @client.describe_client_vpn_target_networks({
        client_vpn_endpoint_id: endpoint
      })

      resp.client_vpn_target_networks.each do |net|
        subnet_resp = @client.describe_subnets({
          subnet_ids: [net.target_network_id]
        })
        subnet = subnet_resp.subnets.first
        groups = get_groups_for_route(endpoint, subnet.cidr_block)
        
        associations.push({
          association_id: net.association_id,
          target_network_id: net.target_network_id,
          status: net.status.code,
          cidr: subnet.cidr_block,
          az: subnet.availability_zone,
          groups: groups.join(' ')
        })
      end

      return associations
    end

  end
end
