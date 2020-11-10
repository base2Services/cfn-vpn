require 'thor'
require 'fileutils'
require 'cfnvpn/deployer'
require 'cfnvpn/certificates'
require 'cfnvpn/compiler'
require 'cfnvpn/log'
require 'cfnvpn/clientvpn'
require 'cfnvpn/globals'

module CfnVpn::Actions
  class Init < Thor::Group
    include Thor::Actions
    

    argument :name

    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :server_cn, required: true, desc: 'server certificate common name'
    class_option :client_cn, desc: 'client certificate common name'
    class_option :easyrsa_local, type: :boolean, default: false, desc: 'run the easyrsa executable from your local rather than from docker'
    class_option :bucket, required: true, desc: 's3 bucket'

    class_option :subnet_ids, required: true, type: :array, desc: 'subnet id to associate your vpn with'
    class_option :cidr, default: '10.250.0.0/16', desc: 'cidr from which to assign client IP addresses'
    class_option :dns_servers, type: :array, desc: 'DNS Servers to push to clients.'
    
    class_option :split_tunnel, type: :boolean, default: true, desc: 'only push routes to the client on the vpn endpoint'
    class_option :internet_route, type: :string, desc: 'create a default route to the internet'
    class_option :protocol, type: :string, default: 'udp', enum: ['udp','tcp'], desc: 'set the protocol for the vpn connections'

    class_option :start, type: :string, desc: 'cloudwatch event cron schedule in UTC to associate subnets to the client vpn'
    class_option :stop, type: :string, desc: 'cloudwatch event cron schedule in UTC to disassociate subnets to the client vpn'

    def self.source_root
      File.dirname(__FILE__)
    end

    def set_loglevel
      CfnVpn::Log.logger.level = Logger::DEBUG if @options['verbose']
    end

    def create_build_directory
      @build_dir = "#{CfnVpn.cfnvpn_path}/#{@name}"
      CfnVpn::Log.logger.debug "creating directory #{@build_dir}"
      FileUtils.mkdir_p(@build_dir)
    end

    def initialize_config
      @config = {
        region: @options['region'],
        subnet_ids: @options['subnet_ids'],
        cidr: @options['cidr'],
        dns_servers: @options['dns_servers'],
        split_tunnel: @options['split_tunnel'],
        internet_route: @options['internet_route'],
        protocol: @options['protocol'],
        start: @options['start'],
        stop: @options['stop'],
        routes: []
      }
    end

    def stack_exist
      @deployer = CfnVpn::Deployer.new(@options['region'],@name)
      if @deployer.does_cf_stack_exist()
        CfnVpn::Log.logger.error "#{@name}-cfnvpn stack already exists in this account in region #{@options['region']}, use the modify command to alter the stack"
        exit 1
      end
    end

    # create certificates
    def generate_server_certificates
      CfnVpn::Log.logger.info "Generating certificates using openvpn easy-rsa"
      cert = CfnVpn::Certificates.new(@build_dir,@name,@options['easyrsa_local'])
      @client_cn = @options['client_cn'] ? @options['client_cn'] : "client-vpn.#{@options['server_cn']}"
      cert.generate_ca(@options['server_cn'],@client_cn)
    end

    def upload_certificates
      cert = CfnVpn::Certificates.new(@build_dir,@name,@options['easyrsa_local'])
      @config[:server_cert_arn] = cert.upload_certificates(@options['region'],'server','server',@options['server_cn'])
      @config[:client_cert_arn] = cert.upload_certificates(@options['region'],@client_cn,'client')
      s3 = CfnVpn::S3.new(@options['region'],@options['bucket'],@name)
      s3.store_object("#{@build_dir}/certificates/ca.tar.gz")
    end

    def deploy_vpn
      compiler = CfnVpn::Compiler.new(@name, @config)
      template_body = compiler.compile
      CfnVpn::Log.logger.info "Launching cloudformation stack #{@name}-cfnvpn in #{@options['region']}"
      change_set, change_set_type = @deployer.create_change_set(template_body: template_body)
      @deployer.wait_for_changeset(change_set.id)
      @deployer.execute_change_set(change_set.id)
      @deployer.wait_for_execute(change_set_type)
      CfnVpn::Log.logger.info "Changeset #{change_set_type} complete"
    end

    def finish
      vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
      @endpoint_id = vpn.get_endpoint_id()
      CfnVpn::Log.logger.info "Client VPN #{@endpoint_id} created. Run `cfn-vpn config #{@name}` to setup the client config"
    end

  end
end
