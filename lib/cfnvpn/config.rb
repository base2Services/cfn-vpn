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
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :key_path, required: true, desc: 'full file path to the client vpn key'
    class_option :crt_path, required: true, desc: 'full file path to the client vpn certificate'

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

    def alter_config
      string = (0...8).map { (65 + rand(26)).chr.downcase }.join
      @config.sub!(@endpoint_id, "#{string}.#{@endpoint_id}")
      @config.concat("\n\ncert #{@options['crt_path']}")
      @config.concat("\nkey #{@options['key_path']}\n")
    end

    def write_config
      config_file = "#{@config_dir}/#{@name}.ovpn"
      File.write(config_file, @config)
      Log.logger.info "downloaded client config #{config_file}"
    end

  end
end
