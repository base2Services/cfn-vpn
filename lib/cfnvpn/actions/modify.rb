require 'thor'
require 'fileutils'
require 'cfnvpn/deployer'
require 'cfnvpn/certificates'
require 'cfnvpn/compiler'
require 'cfnvpn/log'
require 'cfnvpn/clientvpn'
require 'cfnvpn/globals'

module CfnVpn
  class Modify < Thor::Group
    include Thor::Actions
    include CfnVpn::Log

    argument :name

    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :subnet_ids, type: :array, desc: 'subnet id to associate your vpn with'
    class_option :cidr, desc: 'cidr from which to assign client IP addresses'
    class_option :dns_servers, type: :array, desc: 'DNS Servers to push to clients.'

    class_option :split_tunnel, type: :boolean, desc: 'only push routes to the client on the vpn endpoint'
    class_option :internet_route, type: :boolean, desc: 'create a default route to the internet'
    class_option :protocol, type: :string, enum: ['udp','tcp'], desc: 'set the protocol for the vpn connections'

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

    def stack_exist
      @deployer = CfnVpn::Deployer.new(@options['region'],@name)
      if !@deployer.does_cf_stack_exist()
        Log.logger.error "#{@name}-cfnvpn stack doesn't exists in this account in region #{@options['region']}\n Try running `cfn-vpn init #{@name}` to setup the stack"
        exit 1
      end
    end

    def initialize_config
      @config = @deployer.get_outputs_from_stack()
      @config[:subnet_ids] = @config[:subnet_ids].split(',')
      @config[:dns_servers] = @config[:dns_servers].split(',')
      Log.logger.debug "Current config: #{@config}"
      @options.each { |key, value| @config[key.to_sym] = value }
      Log.logger.debug "Modified config: #{@config}"
    end

    def deploy_vpn
      compiler = CfnVpn::Compiler.new(@name, @config)
      template_body = compiler.compile
      Log.logger.info "Modifying cloudformation stack #{@name}-cfnvpn in #{@options['region']}"
      change_set, change_set_type = @deployer.create_change_set(template_body)
      @deployer.wait_for_changeset(change_set.id)
      changes = @deployer.get_change_set(change_set.id)

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

      @deployer.execute_change_set(change_set.id)
      @deployer.wait_for_execute(change_set_type)
      Log.logger.debug "Changeset #{change_set_type} complete"
    end

    def finish
      vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
      @endpoint_id = vpn.get_endpoint_id()
      Log.logger.info "Client VPN #{@endpoint_id} modified."
    end

  end
end
