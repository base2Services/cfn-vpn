require 'thor'
require 'fileutils'
require 'cfnvpn/log'

module CfnVpn::Actions
  class Subnets < Thor::Group
    include Thor::Actions
    include CfnVpn::Log

    argument :name

    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :associate, aliases: :a, desc: 'associate all subnets with the client vpn', type: :boolean
    class_option :disassociate, aliases: :d, desc: 'disassociate all subnets with the client vpn', type: :boolean

    def set_loglevel
      logger.level = Logger::DEBUG if @options['verbose']
    end

    def stack_exist
      @deployer = CfnVpn::Deployer.new(@options['region'],@name)
      if !@deployer.does_cf_stack_exist()
        logger.error "#{@name}-cfnvpn stack doesn't exists in this account and region #{@options['region']}"
        exit 1
      end
    end

    def associated?
      @associated = @deployer.get_parameter_value('AssociateSubnets') == 'true'
    end

    def associate
      if @options[:associate]
        if !@associated
          logger.info "Associating subnets ..."
          change_set, change_set_type = @deployer.create_change_set(parameters: {"AssociateSubnets" => 'true'})
          @deployer.wait_for_changeset(change_set.id)
          @deployer.execute_change_set(change_set.id)
          @deployer.wait_for_execute(change_set_type)
          logger.info "Association complete"
        else
          logger.warn "Client-VPN #{name} subnets are already associated"
        end
      end
    end

    def disassociate
      if @options[:disassociate]
        if @associated
          logger.info "Disassociating subnets ..."
          change_set, change_set_type = @deployer.create_change_set(parameters: {"AssociateSubnets" => 'false'})
          @deployer.wait_for_changeset(change_set.id)
          @deployer.execute_change_set(change_set.id)
          @deployer.wait_for_execute(change_set_type)
          logger.info "Disassociation complete"
        else
          logger.warn "Client-VPN #{name} subnets are already disassociated"
        end
      end
    end

    def get_endpoint
      @vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
      @endpoint_id = @vpn.get_endpoint_id()
    end

    def associations
      associations = @vpn.get_associations(@endpoint_id)
      table = Terminal::Table.new(
        :headings => ['ID', 'Subnet', 'Status', 'CIDR', 'AZ', 'Groups'],
        :rows => associations.map {|ass| ass.values})
      puts table
    end

  end
end
