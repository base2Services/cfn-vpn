require 'thor'
require 'fileutils'
require 'cfnvpn/cloudformation'
require 'cfnvpn/certificates'
require 'cfnvpn/cfhighlander'
require 'cfnvpn/cloudformation'

module CfnVpn
  class Init < Thor::Group
    include Thor::Actions

    argument :name

    class_option :profile, aliases: :p, desc: 'AWS Profile'
    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'

    class_option :server_cn, required: true, desc: 'server certificate common name'
    class_option :client_cn, desc: 'client certificate common name'

    class_option :subnet_id, required: true, desc: 'subnet id to associate your vpn with'
    class_option :cidr, default: '10.250.0.0/16', desc: 'cidr from which to assign client IP addresses'

    def self.source_root
      File.dirname(__FILE__)
    end

    def create_build_directory
      @build_dir = "#{ENV['HOME']}/.cfnvpn/#{@name}"
      FileUtils.mkdir_p(@build_dir)
    end

    def initialize_config
      @config = {}
      @config['subnet_id'] = @options['subnet_id']
      @config['cidr'] = @options['cidr']
    end

    def stack_exist
      @cfn = CfnVpn::Cloudformation.new(@options['region'],@name)
      if @cfn.does_cf_stack_exist()
        say "#{@name}-cfnvpn stack already exists in this account in region #{@options['region']}", :red
        exit 1
      end
    end

    # do certificates exist
    # def server_certificate_exist
    #   @acm = CfnVpn::Acm.new(@options['region'])
    # end

    # create certificates
    def generate_server_certificates
      say "Generating certificates using openvpn easy-rsa", :green
      cert = CfnVpn::Certificates.new(@build_dir)
      @client_cn = @options['client_cn'] ? @options['client_cn'] : "#{@name}.#{@options['server_cn']}"
      puts cert.generate(@options['server_cn'],@client_cn)
    end

    def upload_certificates
      cert = CfnVpn::Certificates.new(@build_dir)
      @config['server_cert_arn'] = cert.upload_certificates(@options['region'],'server','server',@name,@options['server_cn'])
      say "Uploaded server certificate to ACM #{@config['server_cert_arn']}", :green

      @config['client_cert_arn'] = cert.upload_certificates(@options['region'],@client_cn,'client',@name)
      say "Uploaded client certificate to ACM #{@config['client_cert_arn']}", :green
    end

    def deploy_vpn
      template('templates/cfnvpn.cfhighlander.rb.tt', "#{@build_dir}/#{@name}.cfhighlander.rb", @config)
      say "Generating cloudformation",
      cfhl = CfnVpn::CfHiglander.new(@options['region'],@name,@config,@build_dir)
      template_path = cfhl.render()

      cfn = CfnVpn::Cloudformation.new(@options['region'],@name)
      say "Creating changeset", :green
      change_set, change_set_type = cfn.create_change_set(template_path)
      say "Waiting for changeset to be created", :green
      cfn.wait_for_changeset(change_set.id)
      say "Executing the changeset", :green
      cfn.execute_change_set(change_set.id)
      say "Waiting for changeset to #{change_set_type}", :green
      cfn.wait_for_execute(change_set_type)
      say "Changeset #{change_set_type} complete", :green
    end

  end
end
