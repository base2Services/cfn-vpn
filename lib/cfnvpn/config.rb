require 'cfnvpn/clientvpn'

module CfnVpn
  class Config < Thor::Group
    include Thor::Actions

    argument :name

    class_option :profile, desc: 'AWS Profile'
    class_option :region, default: ENV['AWS_REGION'], desc: 'AWS Region'

    def self.source_root
      File.dirname(__FILE__)
    end

    # create config directory
    def create_config_directory
      @home_dir = "#{ENV['HOME']}/.cfnvpn/#{@name}"
      @config_dir = "#{@home_dir}/config"
      FileUtils.mkdir_p(@config_dir)
    end

    # download vpn config
    def download_config
      vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
      @endpoint_id = vpn.get_endpoint_id()
      say "downloading client config for #{@endpoint_id}"
      @config = vpn.get_config(@endpoint_id)
    end

    # download certificates

    # modify config file
    def alter_config
      string = (0...8).map { (65 + rand(26)).chr.downcase }.join
      @config.sub!(@endpoint_id, "#{string}.#{@endpoint_id}")
      @config.concat("\n\ncert #{@home_dir}/certificates/#{@name}.crt")
      @config.concat("\nkey #{@home_dir}/certificates/#{@name}.key\n")
    end

    def write_config
      config_file = "#{@config_dir}/#{@name}.ovpn"
      File.write(config_file, @config)
      say "created config #{config_file}", :green
    end

  end
end
