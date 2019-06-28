require 'thor'
require 'cfnvpn/log'
require 'cfnvpn/s3'

module CfnVpn
  class Client < Thor::Group
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

    def create_certificate
      s3 = CfnVpn::S3.new(@options['region'],@options['bucket'],@name)
      s3.get_object("#{@cert_dir}/ca.tar.gz")
      Log.logger.info "Generating new client certificate #{@options['client_cn']} using openvpn easy-rsa"
      cert = CfnVpn::Certificates.new(@build_dir,@name)
      Log.logger.debug cert.generate_client(@options['client_cn'])
      s3.store_object("#{@cert_dir}/#{@options['client_cn']}.tar.gz")
    end

  end
end
