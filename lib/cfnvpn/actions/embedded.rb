require 'cfnvpn/log'
require 'cfnvpn/s3'
require 'cfnvpn/globals'

module CfnVpn::Actions
  class Embedded < Thor::Group
    include Thor::Actions
    

    argument :name

    class_option :profile, desc: 'AWS Profile'
    class_option :region, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :bucket, required: true, desc: 'S3 bucket'
    class_option :client_cn, required: true, default: false, desc: 'Client certificates to download'
    class_option :easyrsa_local, type: :boolean, default: false, desc: 'run the easyrsa executable from your local rather than from docker'
    class_option :ignore_routes, alias: :i, type: :boolean, desc: 'Ignore client VPN pushed routes and set routes in config file'

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

    def download_config
      vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
      CfnVpn::Log.logger.debug "downloading client config for #{vpn.endpoint_id}"
      @config = vpn.get_config()
      string = (0...8).map { (65 + rand(26)).chr.downcase }.join
      @config.sub!(vpn.endpoint_id, "#{string}.#{vpn.endpoint_id}")
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

    def embed_certs
      cert = CfnVpn::Certificates.new(@build_dir,@name,@options['easyrsa_local'])
      CfnVpn::Log.logger.debug cert.extract_certificate(@options['client_cn'])
      CfnVpn::Log.logger.debug "Reading extracted certificate and private key"
      key = File.read("#{@config_dir}/#{@options['client_cn']}.key")
      crt = File.read("#{@config_dir}/#{@options['client_cn']}.crt")
      CfnVpn::Log.logger.debug "Embedding certificate and private key into config"
      @config.concat("\n<key>\n#{key}\n</key>\n")
      @config.concat("\n<cert>\n#{crt}\n</cert>\n")
    end

    def upload_embedded_config
      @s3 = CfnVpn::S3.new(@options['region'],@options['bucket'],@name)
      @s3.store_embedded_config(@config, @options['client_cn'])
    end

    def get_presigned_url
      @cn = @options['client_cn']
      @config_url = @s3.get_url("#{@name}_#{@cn}.config.ovpn")
      CfnVpn::Log.logger.debug "Config presigned url: #{@config_url}"
    end
    
    def display_url
      CfnVpn::Log.logger.info "Share the below instructions with the user..."
      say "\nDownload the embedded config from the below presigned URL which will expire in 1 hour."
      say "\nConfig:\n"
      say "\tcurl #{@config_url} > #{@name}_#{@cn}.config.ovpn", :cyan
      say "\nOpen #{@name}_#{@cn}.config.ovpn with your favourite openvpn client."
    end

  end

end
