require 'aws-sdk-ssm'
require 'json'
require 'cfnvpn/deployer'

module CfnVpn
  class Config

    def self.get_config(region, name)
      client = Aws::SSM::Client.new(region: region)
      begin
        resp = client.get_parameter({name: "/cfnvpn/config/#{name}"})
        return JSON.parse(resp.parameter.value, {:symbolize_names => true})
      rescue Aws::SSM::Errors::ParameterNotFound => e
        return self.get_config_from_parameter(region, name)
      end
    end

    # to support upgrade from <=0.5.1 to >1.0
    def self.get_config_from_parameter(region, name)
      deployer = CfnVpn::Deployer.new(region, name)
      parameters = deployer.get_parameters_from_stack_hash()
      {
        type: 'certificate',
        server_cert_arn: parameters[:ServerCertificateArn],
        client_cert_arn: parameters[:ClientCertificateArn],
        region: region,
        subnet_ids: [parameters[:AssociationSubnetId]],
        cidr: parameters[:ClientCidrBlock],
        dns_servers: parameters[:DnsServers].split(','),
        split_tunnel: parameters[:SplitTunnel] == "true",
        internet_route: parameters[:InternetRoute] == "true" ? parameters[:AssociationSubnetId] : nil,
        protocol: parameters[:Protocol],
        routes: []
      }
    end

  end
end