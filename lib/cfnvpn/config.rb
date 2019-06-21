require 'cfnvpn/clientvpn'
require 'cfnvpn/ssm'
require 'cfnvpn/log'

module CfnVpn
  class Config < Thor::Group
    include Thor::Actions
    include CfnVpn::Log

    argument :name

    class_option :profile, desc: 'AWS Profile'
    class_option :region, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :force, default: false, type: :boolean, desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    def self.source_root
      File.dirname(__FILE__)
    end

    def set_loglevel
      Log.logger.level = Logger::DEBUG if @options['verbose']
    end

    def create_config_directory
      @home_dir = "#{ENV['HOME']}/.cfnvpn/#{@name}"
      @config_dir = "#{@home_dir}/config"
      Log.logger.debug("Creating config directory #{@config_dir}")
      FileUtils.mkdir_p(@config_dir)
    end

    def download_config
      vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
      @endpoint_id = vpn.get_endpoint_id()
      Log.logger.info "downloading client config for #{@endpoint_id}"
      @config = vpn.get_config(@endpoint_id)
    end

    def download_certificate
      ssm = CfnVpn::SSM.new(@name,@options['region'],@home_dir)
      cert_body = ssm.get_parameter("#{@name}.crt")
      if cert_body
        cert = CfnVpn::Certificates.new(@home_dir,@name)
        cert.write_certificate(cert_body,"#{@name}.crt",@options['force'])
        Log.logger.info "downloaded client certificate #{@name}.crt"
      else
        Log.logger.error "unable to find client certificate #{@name}.crt"
      end
    end

    def download_key
      ssm = CfnVpn::SSM.new(@name,@options['region'],@home_dir)
      cert_body = ssm.get_parameter("#{@name}.key")
      if cert_body
        cert = CfnVpn::Certificates.new(@home_dir,@name)
        cert.write_certificate(cert_body,"#{@name}.key",@options['force'])
        Log.logger.info "downloaded client key #{@name}.key"
      else
        Log.logger.error "unable to find client certificate #{@name}.crt"
      end
    end

    def alter_config
      string = (0...8).map { (65 + rand(26)).chr.downcase }.join
      @config.sub!(@endpoint_id, "#{string}.#{@endpoint_id}")
      @config.concat("\n\ncert #{@config_dir}/#{@name}.crt")
      @config.concat("\nkey #{@config_dir}/#{@name}.key\n")
    end

    def write_config
      config_file = "#{@config_dir}/#{@name}.ovpn"
      File.write(config_file, @config)
      Log.logger.info "downloaded client config #{config_file}"
    end

  end
end
