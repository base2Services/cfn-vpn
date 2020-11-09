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

module CfnVpn::Actions
  class Modify < Thor::Group
    include Thor::Actions
    include CfnVpn::Log

    argument :name

    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :subnet_ids, type: :array, desc: 'overwrite all subnet associations'
    class_option :add_subnet_ids, type: :array, desc: 'add to existing subnet associations'
    class_option :del_subnet_ids, type: :array, desc: 'delete subnet associations'

    class_option :dns_servers, type: :array, desc: 'DNS Servers to push to clients.'
    class_option :no_dns_servers, type: :boolean, desc: 'Remove the DNS Servers from the client vpn'

    class_option :cidr, desc: 'cidr from which to assign client IP addresses'
    class_option :split_tunnel, type: :boolean, desc: 'only push routes to the client on the vpn endpoint'
    class_option :internet_route, type: :string, desc: '[subnet-id] create a default route to the internet through a subnet'
    class_option :protocol, type: :string, enum: ['udp','tcp'], desc: 'set the protocol for the vpn connections'

    class_option :start, type: :string, desc: 'cloudwatch event cron schedule in UTC to associate subnets to the client vpn'
    class_option :stop, type: :string, desc: 'cloudwatch event cron schedule in UTC to disassociate subnets to the client vpn'

    def self.source_root
      File.dirname(__FILE__)
    end

    def set_loglevel
      logger.level = Logger::DEBUG if @options['verbose']
    end

    def create_build_directory
      @build_dir = "#{CfnVpn.cfnvpn_path}/#{@name}"
      logger.debug "creating directory #{@build_dir}"
      FileUtils.mkdir_p(@build_dir)
    end

    def stack_exist
      @deployer = CfnVpn::Deployer.new(@options['region'],@name)
      if !@deployer.does_cf_stack_exist()
        logger.error "#{@name}-cfnvpn stack doesn't exists in this account in region #{@options['region']}\n Try running `cfn-vpn init #{@name}` to setup the stack"
        exit 1
      end
    end

    def initialize_config
      @config = CfnVpn::Config.get_config(@options[:region], @name)

      logger.debug "Current config:\n#{@config}"

      @options.each do |key, value|
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

      logger.debug "Modified config:\n#{@config}"
    end

    def deploy_vpn
      compiler = CfnVpn::Compiler.new(@name, @config)
      template_body = compiler.compile
      logger.info "Creating cloudformation changeset for stack #{@name}-cfnvpn in #{@options['region']}"
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

      logger.info "Cloudformation changeset changes:"
      puts "\n"
      continue = yes? "Continue?", :green
      if !continue
        logger.info("Cancelled cfn-vpn modifiy #{@name}")
        exit 1
      end

      @deployer.execute_change_set(change_set.id)
      @deployer.wait_for_execute(change_set_type)
      logger.info "Changeset #{change_set_type} complete"
    end

    def finish
      vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
      @endpoint_id = vpn.get_endpoint_id()
      logger.info "Client VPN #{@endpoint_id} modified."
    end

  end
end
