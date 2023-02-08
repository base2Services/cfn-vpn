require 'thor'
require 'fileutils'
require 'cfnvpn/cloudformation'
require 'cfnvpn/certificates'
require 'cfnvpn/cfhighlander'
require 'cfnvpn/cloudformation'
require 'cfnvpn/log'
require 'cfnvpn/clientvpn'
require 'cfnvpn/globals'

module CfnVpn
  class RenewCertificate < Thor::Group
    include Thor::Actions
    include CfnVpn::Log

    argument :name

    class_option :profile, aliases: :p, desc: 'AWS Profile'
    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :server_cn, required: true, desc: 'server certificate common name'
    class_option :client_cn, desc: 'client certificate common name'
    class_option :easyrsa_local, type: :boolean, default: false, desc: 'run the easyrsa executable from your local rather than from docker'
    class_option :certificate_expiry, type: :string, desc: 'value in days for when the server certificates expire, defaults to 825 days'
    class_option :rebuild, type: :boolean, default: false, desc: 'generates new certificates from the existing CA for certiciate type VPNs'
    class_option :bucket, required: true, desc: 's3 bucket'

    def self.source_root
      File.dirname(__FILE__)
    end

    def set_loglevel
      Log.logger.level = Logger::DEBUG if @options['verbose']
    end

    def create_build_directory
      @build_dir = "#{CfnVpn.cfnvpn_path}/#{@name}"
      Log.logger.debug "creating directory #{@build_dir}"
      FileUtils.mkdir_p(@build_dir)
    end

    def initialize_config
      @config = {}
      @config['parameters'] = {}
      @config['template_version'] = '0.2.0'
    end

    def stack_exist
      @cfn = CfnVpn::Cloudformation.new(@options['region'],@name)
      if !@cfn.does_cf_stack_exist()
        Log.logger.error "#{@name}-cfnvpn stack doesn't exists in this account in region #{@options['region']}\n Try running `cfn-vpn init #{@name}` to setup the stack"
        exit 1
      end
    end

    def set_client_cn
      @client_cn = @options['client_cn'] ? @options['client_cn'] : "client-vpn.#{@options['server_cn']}"
    end

    # create certificates
    def generate_server_certificates
      cert = CfnVpn::Certificates.new(@build_dir,@name,@options['easyrsa_local'])
      if @options['rebuild']
        Log.logger.info "rebuilding certificates using openvpn easy-rsa"
        cert.rebuild(@options['server_cn'],@client_cn,@options['certificate_expiry'])
      else
        Log.logger.info "rebuilding certificates using openvpn easy-rsa"
        cert.renew(@options['server_cn'],@client_cn,@options['certificate_expiry'])
      end
    end

    def upload_certificates
      cert = CfnVpn::Certificates.new(@build_dir,@name,@options['easyrsa_local'])
      @config['parameters']['ServerCertificateArn'] = cert.upload_certificates(@options['region'],'server','server',@options['server_cn'])
      @config['parameters']['ClientCertificateArn'] = cert.upload_certificates(@options['region'],@client_cn,'client')
      s3 = CfnVpn::S3.new(@options['region'],@options['bucket'],@name)
      s3.store_object("#{@build_dir}/certificates/ca.tar.gz")
    end

    def deploy_vpn
      template('templates/cfnvpn.cfhighlander.rb.tt', "#{@build_dir}/#{@name}.cfhighlander.rb", @config, force: true)
      Log.logger.debug "Generating cloudformation from #{@build_dir}/#{@name}.cfhighlander.rb"
      cfhl = CfnVpn::CfHiglander.new(@options['region'],@name,@config,@build_dir)
      template_path = cfhl.render()
      Log.logger.debug "Cloudformation template #{template_path} generated and validated"

      Log.logger.info "Modifying cloudformation stack #{@name}-cfnvpn in #{@options['region']}"
      cfn = CfnVpn::Cloudformation.new(@options['region'],@name)
      change_set, change_set_type = cfn.create_change_set(template_path,@config['parameters'])
      cfn.wait_for_changeset(change_set.id)
      changes = cfn.get_change_set(change_set.id)

      Log.logger.warn("The following changes to the cfnvpn stack will be made")
      changes.changes.each do |change|
        Log.logger.warn("ID: #{change.resource_change.logical_resource_id} Action: #{change.resource_change.action}")
        change.resource_change.details.each do |details|
          Log.logger.warn("Name: #{details.target.name} Attribute: #{details.target.attribute} Cause: #{details.causing_entity}")
        end
      end

      continue = yes? "Continue?", :green
      if !continue
        Log.logger.error("Cancelled cfn-vpn modifiy #{@name}")
        exit 1
      end

      cfn.execute_change_set(change_set.id)
      cfn.wait_for_execute(change_set_type)
      Log.logger.debug "Changeset #{change_set_type} complete"
    end

    def finish
      vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
      @endpoint_id = vpn.get_endpoint_id()
      Log.logger.info "Client VPN #{@endpoint_id} modified."
    end

  end
end