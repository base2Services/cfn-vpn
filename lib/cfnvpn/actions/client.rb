require 'thor'
require 'fileutils'
require 'cfnvpn/log'
require 'cfnvpn/s3'
require 'cfnvpn/globals'

module CfnVpn::Actions
  class Client < Thor::Group
    include Thor::Actions  

    argument :name

    class_option :profile, aliases: :p, desc: 'AWS Profile'
    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :bucket, desc: 's3 bucket', required: true
    class_option :client_cn, desc: 'client certificate common name', required: true
    class_option :easyrsa_local, type: :boolean, default: false, desc: 'run the easyrsa executable from your local rather than from docker'
    class_option :certificate_expiry, type: :string, desc: 'value in days for when the client certificates expire, defaults to 825 days'

    def self.source_root
      File.dirname(__FILE__)
    end

    def set_loglevel
      CfnVpn::Log.logger.level = Logger::DEBUG if @options['verbose']
    end

    def set_directory
      @build_dir = "#{CfnVpn.cfnvpn_path}/#{@name}"
      @cert_dir = "#{@build_dir}/certificates"
      FileUtils.mkdir_p(@cert_dir)
    end

    def create_certificate
      s3 = CfnVpn::S3.new(@options['region'],@options['bucket'],@name)
      s3.get_object("#{@cert_dir}/ca.tar.gz")
      CfnVpn::Log.logger.info "Generating new client certificate #{@options['client_cn']} using openvpn easy-rsa"
      cert = CfnVpn::Certificates.new(@build_dir,@name,@options['easyrsa_local'])
      CfnVpn::Log.logger.debug cert.generate_client(@options['client_cn'],@options['certificate_expiry'])
      s3.store_object("#{@cert_dir}/#{@options['client_cn']}.tar.gz")
    end

  end
end
