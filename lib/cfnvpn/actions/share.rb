require 'cfnvpn/log'
require 'cfnvpn/s3'

module CfnVpn::Actions
  class Share < Thor::Group
    include Thor::Actions
    include CfnVpn::Log

    argument :name

    class_option :profile, desc: 'AWS Profile'
    class_option :region, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :bucket, required: true, desc: 's3 bucket'
    class_option :client_cn, required: true, desc: "client certificates to download"
    class_option :ignore_routes, alias: :i, type: :boolean, desc: "Ignore client VPN pushed routes and set routes in config file"

    def self.source_root
      File.dirname(__FILE__)
    end

    def set_loglevel
      logger.level = Logger::DEBUG if @options['verbose']
    end

    def copy_config_to_s3
      vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
      @endpoint_id = vpn.get_endpoint_id()
      logger.debug "downloading client config for #{@endpoint_id}"
      @config = vpn.get_config(@endpoint_id)
      string = (0...8).map { (65 + rand(26)).chr.downcase }.join
      @config.sub!(@endpoint_id, "#{string}.#{@endpoint_id}")
    end

    def add_routes
      if @options['ignore_routes']
        logger.debug "Ignoring routes pushed by the client vpn"
        @config.concat("\nroute-nopull\n")
        vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
        routes = vpn.get_route_with_mask
        logger.debug "Found routes #{routes}"
        routes.each do |r|
          @config.concat("route #{r[:route]} #{r[:mask]}\n")
        end
        dns_servers = vpn.get_dns_servers()
        if dns_servers.any?
          logger.debug "Found DNS servers #{dns_servers.join(' ')}"
          @config.concat("dhcp-option DNS #{dns_servers.first}\n")
        end
      end
    end

    def upload_config
      @s3 = CfnVpn::S3.new(@options['region'],@options['bucket'],@name)
      @s3.store_config(@config)
    end

    def get_certificate_url
      @certificate_url = @s3.get_url("#{@options['client_cn']}.tar.gz")
      logger.debug "Certificate presigned url: #{@certificate_url}"
    end

    def get_config_url
      @config_url = @s3.get_url("#{@name}.config.ovpn")
      logger.debug "Config presigned url: #{@config_url}"
    end

    def display_instructions
      logger.info "Share the bellow instruction with the user..."
      say "\nDownload the certificates and config from the bellow presigned URLs which will expire in 1 hour."
      say "\nCertificate:"
      say "\tcurl #{@certificate_url} > #{@options['client_cn']}.tar.gz", :cyan
      say "\nConfig:\n"
      say "\tcurl #{@config_url} > #{@name}.config.ovpn", :cyan
      say "\nExtract the certificates from the tar and place into a safe location."
      say "\ttar xzfv #{@options['client_cn']}.tar.gz -C <path> --strip 2", :cyan
      say "\nModify #{@name}.config.ovpn to include the full location of your extracted certificates"
      say "\techo \"key /<path>/#{@options['client_cn']}.key\" >> #{@name}.config.ovpn", :cyan
      say "\techo \"cert /<path>/#{@options['client_cn']}.crt\" >> #{@name}.config.ovpn", :cyan
      say "\nOpen #{@name}.config.ovpn with your favourite openvpn client."
    end

  end
end
