require 'fileutils'
require 'cfnvpn/acm'
require 'cfnvpn/ssm'
require 'cfnvpn/log'

module CfnVpn
  class Certificates
    include CfnVpn::Log

    def initialize(build_dir,cfnvpn_name)
      @cfnvpn_name = cfnvpn_name
      @config_dir = "#{build_dir}/config"
      @cert_dir = "#{build_dir}/certificates"
      FileUtils.mkdir_p(@cert_dir)
    end

    def generate(server_cn,client_cn)
      cmd = ["docker", "run", "-it", "--rm"]
      cmd << "-e EASYRSA_REQ_CN=#{server_cn}"
      cmd << "-e EASYRSA_CLIENT_CN=#{client_cn}"
      cmd << "-v #{@cert_dir}:/easy-rsa/output"
      cmd << "base2/aws-client-vpn:3.0.5"
      return `#{cmd.join(' ')}`
    end

    def upload_certificates(region,cert,type,cn=nil)
      cn = cn.nil? ? cert : cn
      acm = CfnVpn::Acm.new(region, @cert_dir)
      arn = acm.import_certificate("#{cert}.crt", "#{cert}.key", "ca.crt")
      Log.logger.debug "Uploaded #{type} certificate to ACM #{arn}"
      acm.tag_certificate(arn,cn,type,@cfnvpn_name)
      return arn
    end

    def store_certificate(region,cert)
      ssm = CfnVpn::SSM.new(@cfnvpn_name, region, @cert_dir)
      ssm.put_parameter(cert)
    end

    def write_certificate(cert_body,name,force)
      file = "#{@config_dir}/#{name}"
      if File.file?(file)
        if force
          Log.logger.warn "overriding existing #{name}"
          File.write(file, cert_body)
        else
          Log.logger.info "#{name} already exists"
        end
      else
        File.write(file, cert_body)
      end
    end

  end
end
