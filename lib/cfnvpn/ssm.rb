require 'aws-sdk-ssm'
require 'fileutils'
require 'cfnvpn/log'

module CfnVpn
  class SSM
    include CfnVpn::Log

    def initialize(name,region,cert_dir)
      @name = name
      @cert_dir = cert_dir
      @path_prefix = "/cfnvpn/#{@name}"
      @client = Aws::SSM::Client.new(region: region)
    end

    def get_parameter(cert)
      begin
        resp = @client.get_parameter({
          name: "#{@path_prefix}/#{cert}",
          with_decryption: true
        })
      rescue Aws::SSM::Errors::ParameterNotFound
        Log.logger.debug("Parameter #{@path_prefix}/#{cert} not found")
        return false
      end
      Log.logger.debug("found parameter #{@path_prefix}/#{cert}")
      return resp.parameter.value
    end

    def put_parameter(cert)
      certificate = File.read("#{@cert_dir}/#{cert}")
      Log.logger.debug("Reading certificate #{@cert_dir}/#{cert}")
      ext = cert.split('.').last
      @client.put_parameter({
        name: "#{@path_prefix}/#{@name}.#{ext}",
        description: "cfn-vpn #{@name} #{cert}",
        value: certificate,
        type: "SecureString",
        overwrite: false,
        tags: [
          { key: "cfnvpn:name", value: @name },
          { key: "cfnvpn:certificate", value: cert }
        ],
        tier: "Advanced",
      })
      Log.logger.info("Stored #{cert} in ssm parameter #{@path_prefix}/#{@name}.#{ext}")
    end

  end
end
