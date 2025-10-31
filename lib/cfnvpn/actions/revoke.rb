require 'thor'
require 'cfnvpn/log'
require 'cfnvpn/s3'
require 'cfnvpn/globals'

module CfnVpn::Actions
  class Revoke < Thor::Group
    include Thor::Actions
    

    argument :name

    class_option :profile, aliases: :p, desc: 'AWS Profile'
    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :bucket, desc: 's3 bucket', required: true
    class_option :client_cn, desc: 'client certificate common name', required: true
    class_option :easyrsa_local, type: :boolean, default: false, desc: 'run the easyrsa executable from your local rather than from docker'

    def self.source_root
      File.dirname(__FILE__)
    end

    def set_loglevel
      CfnVpn::Log.logger.level = Logger::DEBUG if @options['verbose']
    end

    def set_directory
      @build_dir = "#{CfnVpn.cfnvpn_path}/#{@name}"
      @cert_dir = "#{@build_dir}/certificates"
    end

    def revoke_certificate
      cert = CfnVpn::Certificates.new(@build_dir,@name,@options['easyrsa_local'])
      s3 = CfnVpn::S3.new(@options['region'],@options['bucket'],@name)
      s3.get_object("#{@cert_dir}/ca.tar.gz")
      s3.get_object("#{@cert_dir}/#{@options['client_cn']}.tar.gz")
      CfnVpn::Log.logger.info "Generating new client certificate #{@options['client_cn']} using openvpn easy-rsa"
      CfnVpn::Log.logger.debug cert.revoke_client(@options['client_cn'])
      
      # persist index.txt which contains previous CRL back to s3
      system("tar xzfv #{@cert_dir}/ca.tar.gz --directory #{@build_dir}")
      FileUtils.cp(["#{@cert_dir}/index.txt"], "#{@build_dir}/pki/")
      system("tar czfv #{@cert_dir}/ca.tar.gz -C #{@build_dir} pki/")
      s3.store_object("#{@cert_dir}/ca.tar.gz")
    end

    def apply_rekocation_list
      vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
      vpn.put_revoke_list("#{@cert_dir}/crl.pem")
      CfnVpn::Log.logger.info("revoked client #{@options['client_cn']} from #{vpn.endpoint_id}")
    end

  end
end
