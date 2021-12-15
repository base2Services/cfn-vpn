require 'thor'
require 'fileutils'
require 'cfnvpn/deployer'
require 'cfnvpn/certificates'
require 'cfnvpn/compiler'
require 'cfnvpn/log'
require 'cfnvpn/clientvpn'
require 'cfnvpn/globals'
require 'cfnvpn/s3_bucket'

module CfnVpn::Actions
  class Init < Thor::Group
    include Thor::Actions
    

    argument :name

    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :server_cn, required: true, desc: 'server certificate common name'
    class_option :client_cn, desc: 'client certificate common name'
    class_option :easyrsa_local, type: :boolean, default: false, desc: 'run the easyrsa executable from your local rather than from docker'
    class_option :bucket, desc: 's3 bucket, if not set one will be generated for you'

    class_option :subnet_ids, required: true, type: :array, desc: 'subnet id to associate your vpn with'
    class_option :default_groups, default: [], type: :array, desc: 'groups to allow through the subnet associations when using federated auth'
    class_option :cidr, default: '10.250.0.0/16', desc: 'cidr from which to assign client IP addresses'
    class_option :dns_servers, default: [], type: :array, desc: 'DNS Servers to push to clients.'
    
    class_option :split_tunnel, type: :boolean, default: true, desc: 'only push routes to the client on the vpn endpoint'
    class_option :internet_route, type: :string, desc: '[subnet-id] create a default route to the internet through a subnet'
    class_option :protocol, type: :string, default: 'udp', enum: ['udp','tcp'], desc: 'set the protocol for the vpn connections'

    class_option :start, type: :string, desc: 'cloudwatch event cron schedule in UTC to associate subnets to the client vpn'
    class_option :stop, type: :string, desc: 'cloudwatch event cron schedule in UTC to disassociate subnets to the client vpn'

    class_option :saml_arn, desc: 'IAM SAML identity provider arn if using SAML federated authentication'
    class_option :saml_self_service_arn, desc: 'IAM SAML identity provider arn for the self service portal'
    class_option :directory_id, desc: 'AWS Directory Service directory id if using Active Directory authentication'

    class_option :slack_webhook_url, type: :string, desc: 'slack webhook url to send notifications from the scheduler and route populator'
    class_option :auto_limit_increase, type: :boolean, default: true, desc: 'automatically request a AWS service quota increase if limits are hit for route entry and authorization rule limits'
    
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
        saml_arn: @options['saml_arn'],
        saml_self_service_arn: @options['saml_self_service_arn'],
        directory_id: @options['directory_id'],
        slack_webhook_url: @options['slack_webhook_url'],
        auto_limit_increase: @options['auto_limit_increase'],
        routes: []
      }
    end

    def create_bucket_if_bucket_not_set
      if !@options['bucket']
        CfnVpn::Log.logger.info "creating s3 bucket"
        bucket = CfnVpn::S3Bucket.new(@options['region'], @name)
        bucket_name = bucket.generate_bucket_name
        bucket.create_bucket(bucket_name)
        @config[:bucket] = bucket_name
      else
        @config[:bucket] = @options['bucket']
      end
    end

    def set_type
      if @options['saml_arn']
        @config[:type] = 'federated'
        @config[:default_groups] = @options['default_groups']
      elsif @options['directory_id']
        @config[:type] = 'active-directory'
        @config[:default_groups] = @options['default_groups']
      else
        @config[:type] = 'certificate'
        @config[:default_groups] = []
      end
      CfnVpn::Log.logger.info "initialising #{@config[:type]} client vpn"
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
      if @config[:type] == 'certificate'
         # we only need the server certificate to ACM if it is a SAML federated client vpn
        @config[:client_cert_arn] = cert.upload_certificates(@options['region'],@client_cn,'client')
        # and only need to upload the certs to s3 if using certificate authenitcation
        s3 = CfnVpn::S3.new(@options['region'],@config[:bucket],@name)
        s3.store_object("#{@build_dir}/certificates/ca.tar.gz")
      end
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
      CfnVpn::Log.logger.info "Client VPN #{vpn.endpoint_id} created. Run `cfn-vpn config #{@name}` to setup the client config"
    end

  end
end
