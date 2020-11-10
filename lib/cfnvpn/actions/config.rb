require 'cfnvpn/clientvpn'
require 'cfnvpn/log'
require 'cfnvpn/globals'

module CfnVpn::Actions
  class Config < Thor::Group
    include Thor::Actions
    

    argument :name

    class_option :profile, desc: 'AWS Profile'
    class_option :region, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean
    class_option :bucket, required: true, desc: 's3 bucket'
    class_option :client_cn, required: true, desc: "client certificates to download"
    class_option :easyrsa_local, type: :boolean, default: false, desc: 'run the easyrsa executable from your local rather than from docker'
    class_option :ignore_routes, alias: :i, type: :boolean, desc: "Ignore client VPN pushed routes and set routes in config file"

    def self.source_root
      File.dirname(__FILE__)
    end

    def set_loglevel
      CfnVpn::Log.logger.level = Logger::DEBUG if @options['verbose']
    end

    def create_config_directory
      @build_dir = "#{CfnVpn.cfnvpn_path}/#{@name}"
      @config_dir = "#{@build_dir}/config"
      CfnVpn::Log.logger.debug("Creating config directory #{@config_dir}")
      FileUtils.mkdir_p(@config_dir)
    end

    def download_config
      vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
      @endpoint_id = vpn.get_endpoint_id()
      CfnVpn::Log.logger.info "downloading client config for #{@endpoint_id}"
      @config = vpn.get_config(@endpoint_id)
    end

    def download_certificates
      download = true
      if File.exists?("#{@config_dir}/#{@options['client_cn']}.crt")
        download = yes? "Certificates for #{@options['client_cn']} already exist in #{@config_dir}. Do you want to download again? ", :green
      end

      if download
        CfnVpn::Log.logger.info "Downloading certificates for #{@options['client_cn']} to #{@config_dir}"
        s3 = CfnVpn::S3.new(@options['region'],@options['bucket'],@name)
        s3.get_object("#{@config_dir}/#{@options['client_cn']}.tar.gz")
        cert = CfnVpn::Certificates.new(@build_dir,@name,@options['easyrsa_local'])
        CfnVpn::Log.logger.debug cert.extract_certificate(@options['client_cn'])
      end
    end

    def alter_config
      string = (0...8).map { (65 + rand(26)).chr.downcase }.join
      @config.sub!(@endpoint_id, "#{string}.#{@endpoint_id}")
      @config.concat("\n\ncert #{@config_dir}/#{@options['client_cn']}.crt")
      @config.concat("\nkey #{@config_dir}/#{@options['client_cn']}.key\n")
    end

    def add_routes
      if @options['ignore_routes']
        CfnVpn::Log.logger.debug "Ignoring routes pushed by the client vpn"
        @config.concat("\nroute-nopull\n")
        vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
        routes = vpn.get_route_with_mask
        CfnVpn::Log.logger.debug "Found routes #{routes}"
        routes.each do |r|
          @config.concat("route #{r[:route]} #{r[:mask]}\n")
        end
        dns_servers = vpn.get_dns_servers()
        if dns_servers.any?
          CfnVpn::Log.logger.debug "Found DNS servers #{dns_servers.join(' ')}"
          @config.concat("dhcp-option DNS #{dns_servers.first}\n")
        end
      end
    end

    def write_config
      config_file = "#{@config_dir}/#{@name}.ovpn"
      File.write(config_file, @config)
      CfnVpn::Log.logger.info "downloaded client config #{config_file}"
    end

  end
end
