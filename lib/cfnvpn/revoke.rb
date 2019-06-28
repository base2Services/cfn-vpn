require 'thor'
require 'cfnvpn/log'
require 'cfnvpn/s3'

module CfnVpn
  class Revoke < Thor::Group
    include Thor::Actions
    include CfnVpn::Log

    argument :name

    class_option :profile, aliases: :p, desc: 'AWS Profile'
    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :bucket, desc: 's3 bucket', required: true
    class_option :client_cn, desc: 'client certificate common name', required: true

    def self.source_root
      File.dirname(__FILE__)
    end

    def set_loglevel
      Log.logger.level = Logger::DEBUG if @options['verbose']
    end

    def set_directory
      @build_dir = "#{ENV['HOME']}/.cfnvpn/#{@name}"
      @cert_dir = "#{@build_dir}/certificates"
    end

    def revoke_certificate
      cert = CfnVpn::Certificates.new(@build_dir,@name)
      s3 = CfnVpn::S3.new(@options['region'],@options['bucket'],@name)
      s3.get_object("#{@cert_dir}/ca.tar.gz")
      s3.get_object("#{@cert_dir}/#{@options['client_cn']}.tar.gz")
      Log.logger.info "Generating new client certificate #{@options['client_cn']} using openvpn easy-rsa"
      Log.logger.debug cert.revoke_client(@options['client_cn'])
    end

    def apply_rekocation_list
      vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
      endpoint_id = vpn.get_endpoint_id()
      vpn.put_revoke_list(endpoint_id,"#{@cert_dir}/crl.pem")
      Log.logger.info("revoked client #{@options['client_cn']} from #{endpoint_id}")
    end

  end
end
