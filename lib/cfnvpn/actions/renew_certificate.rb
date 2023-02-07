require 'thor'
require 'fileutils'
require 'cfnvpn/deployer'
require 'cfnvpn/certificates'
require 'cfnvpn/compiler'
require 'cfnvpn/log'
require 'cfnvpn/clientvpn'
require 'cfnvpn/globals'
require 'cfnvpn/s3_bucket'
require 'cfnvpn/acm'

module CfnVpn::Actions
  class RenewCertificate < Thor::Group
    include Thor::Actions

    argument :name

    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :easyrsa_local, type: :boolean, default: false, desc: 'run the easyrsa executable from your local rather than from docker'
    class_option :certificate_expiry, type: :string, desc: 'value in days for when the server certificates expire, defaults to 825 days'
    class_option :rebuild, type: :boolean, default: false, desc: 'generates new certificates from the existing CA for certiciate type VPNs'
    class_option :bucket, desc: 's3 bucket, if not set one will be generated for you'

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
      @cert_dir = "#{@build_dir}/certificates"
      FileUtils.mkdir_p(@cert_dir)
    end

    def stack_exist
      @deployer = CfnVpn::Deployer.new(@options['region'],@name)
      if !@deployer.does_cf_stack_exist()
        CfnVpn::Log.logger.error "#{@name}-cfnvpn stack doesn't exists in this account in region #{@options['region']}\n Try running `cfn-vpn init #{@name}` to setup the stack"
        exit 1
      end
    end

    def initialize_config
      @config = CfnVpn::Config.get_config(@options['region'], @name)
    end

    def set_client_cn
      @client_cn = nil
      if @config[:type] == 'certificate'
        acm = CfnVpn::Acm.new(@options['region'], @cert_dir)
        @client_cn = acm.get_certificate_tags(@config[:client_cert_arn],'Name')
        CfnVpn::Log.logger.info "Client CN #{@client_cn}"
      end
    end

    def renew_certificates
      if @config[:type] == 'certificate'
        s3 = CfnVpn::S3.new(@options['region'],@options['bucket'],@name)
        s3.get_object("#{@cert_dir}/ca.tar.gz")

        if @options['rebuild']
          CfnVpn::Log.logger.info "rebuilding server and #{@client_cn} certificates"
          cert = CfnVpn::Certificates.new(@build_dir,@name,@options['easyrsa_local'])
          cert.rebuild(@config[:server_cn],@client_cn,@options['certificate_expiry'])
        else
          CfnVpn::Log.logger.info "renewing server and #{@client_cn} certificates"
          cert = CfnVpn::Certificates.new(@build_dir,@name,@options['easyrsa_local'])
          cert.renew(@config[:server_cn],@client_cn,@options['certificate_expiry'])
        end
      else
        CfnVpn::Log.logger.info "recreating server and #{@client_cn} certificates with a new CA"
        cert = CfnVpn::Certificates.new(@build_dir,@name,@options['easyrsa_local'])
        cert.generate_ca(@options['server_cn'],@options['certificate_expiry'])
      end
    end

    def upload_certificates
      cert = CfnVpn::Certificates.new(@build_dir,@name,@options['easyrsa_local'])
      @config[:server_cert_arn] = cert.upload_certificates(@options['region'],'server','server',@config[:server_cn])
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
      CfnVpn::Log.logger.info "Creating cloudformation changeset for stack #{@name}-cfnvpn in #{@options['region']}"
      change_set, change_set_type = @deployer.create_change_set(template_body: template_body)
      @deployer.wait_for_changeset(change_set.id)
      changeset_response = @deployer.get_change_set(change_set.id)

      changes = {"Add" => [], "Modify" => [], "Remove" => []}
      change_colours = {"Add" => "green", "Modify" => 'yellow', "Remove" => 'red'}

      changeset_response.changes.each do |change|
        action = change.resource_change.action
        changes[action].push([
          change.resource_change.logical_resource_id,
          change.resource_change.resource_type,
          change.resource_change.replacement ? change.resource_change.replacement : 'N/A',
          change.resource_change.details.collect {|detail| detail.target.name }.join(' , ')
        ])
      end

      changes.each do |type, rows|
        next if !rows.any?
        puts "\n"
        table = Terminal::Table.new(
          :title => type,
          :headings => ['Logical Resource Id', 'Resource Type', 'Replacement', 'Changes'],
          :rows => rows)
        puts table.to_s.send(change_colours[type])
      end

      CfnVpn::Log.logger.info "Cloudformation changeset changes:"
      puts "\n"
      continue = yes? "Continue?", :green
      if !continue
        CfnVpn::Log.logger.info("Cancelled cfn-vpn modifiy #{@name}")
        exit 1
      end

      @deployer.execute_change_set(change_set.id)
      @deployer.wait_for_execute(change_set_type)
      CfnVpn::Log.logger.info "Changeset #{change_set_type} complete"
    end

  end
end