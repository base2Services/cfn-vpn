require 'thor'
require 'fileutils'
require 'terminal-table'
require 'cfnvpn/deployer'
require 'cfnvpn/certificates'
require 'cfnvpn/compiler'
require 'cfnvpn/log'
require 'cfnvpn/clientvpn'
require 'cfnvpn/globals'
require 'cfnvpn/config'
require 'cfnvpn/s3_bucket'

module CfnVpn::Actions
  class Modify < Thor::Group
    include Thor::Actions
    

    argument :name

    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :subnet_ids, type: :array, desc: 'overwrite all subnet associations'
    class_option :add_subnet_ids, type: :array, desc: 'add to existing subnet associations'
    class_option :del_subnet_ids, type: :array, desc: 'delete subnet associations'

    class_option :default_groups, type: :array, desc: 'groups to allow through the subnet associations when using federated auth'

    class_option :dns_servers, type: :array, desc: 'DNS Servers to push to clients.'
    class_option :no_dns_servers, type: :boolean, desc: 'Remove the DNS Servers from the client vpn'

    class_option :cidr, desc: 'cidr from which to assign client IP addresses'
    class_option :split_tunnel, type: :boolean, desc: 'only push routes to the client on the vpn endpoint'
    class_option :internet_route, type: :string, desc: '[subnet-id] create a default route to the internet through a subnet'
    class_option :protocol, type: :string, enum: ['udp','tcp'], desc: 'set the protocol for the vpn connections'

    class_option :start, type: :string, desc: 'cloudwatch event cron schedule in UTC to associate subnets to the client vpn'
    class_option :stop, type: :string, desc: 'cloudwatch event cron schedule in UTC to disassociate subnets to the client vpn'

    class_option :param_yaml, type: :string, desc: 'pass in cfnvpn params through YAML file'

    class_option :bucket, desc: 's3 bucket'

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

    def stack_exist
      @deployer = CfnVpn::Deployer.new(@options['region'],@name)
      if !@deployer.does_cf_stack_exist()
        CfnVpn::Log.logger.error "#{@name}-cfnvpn stack doesn't exists in this account in region #{@options['region']}\n Try running `cfn-vpn init #{@name}` to setup the stack"
        exit 1
      end
    end

    def initialize_config
      @config = CfnVpn::Config.get_config(@options[:region], @name)

      CfnVpn::Log.logger.debug "Current config:\n#{@config}"

      if @options[:param_yaml]
        CfnVpn::Log.logger.debug "Loading config from YAML file #{@options[:param_yaml]}"
        @config = CfnVpn::Config.get_config_from_yaml_file(@options[:param_yaml])
      else
        CfnVpn::Log.logger.debug "Loading config from options"
        @options.each do |key, value|
          next if [:verbose].include? key
          @config[key.to_sym] = value
        end

        if @options['add_subnet_ids']
          @config[:subnet_ids].concat @options['add_subnet_ids']
        end

        if @options['del_subnet_ids']
          @config[:subnet_ids].reject!{ |subnet| @options['del_subnet_ids'].include? subnet }
        end

        if @options['no_dns_servers']
          @config[:dns_servers] = []
        end
      end

      if (@config[:saml_arn] || @config[:directory_id]) && @options[:default_groups]
        @config[:default_groups] = @options[:default_groups]
      end

      CfnVpn::Log.logger.debug "Modified config:\n#{@config}"
    end

    def create_bucket_if_bucket_not_set
      if !@options['bucket'] && !@config.has_key?(:bucket)
        if yes? "no s3 bucket supplied in the command or found in the config, select (Y) to generate a new one ot select (N) and re run teh command with the --bucket flag to import the existing bucket." 
          CfnVpn::Log.logger.info "creating s3 bucket"
          bucket = CfnVpn::S3Bucket.new(@options['region'], @name)
          bucket_name = bucket.generate_bucket_name
          bucket.create_bucket(bucket_name)
          @config[:bucket] = bucket_name
        else
          CfnVpn::Log.logger.info "rerun cfn-vpn modify #{name} command with the --bucket [BUCKET] flag"
          exit 1
        end
      elsif @options['bucket']
        @config[:bucket] = @options['bucket']
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

    def finish
      vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
      @endpoint_id = vpn.get_endpoint_id()
      CfnVpn::Log.logger.info "Client VPN #{@endpoint_id} modified."
    end

  end
end
