require 'aws-sdk-ssm'
require 'json'

module CfnVpn
  class Config

    def self.get_config(region, name)
      client = Aws::SSM::Client.new(region: region)
      resp = client.get_parameter({name: "/cfnvpn/config/#{name}"})
      return JSON.parse(resp.parameter.value, {:symbolize_names => true})
    end

  end
end