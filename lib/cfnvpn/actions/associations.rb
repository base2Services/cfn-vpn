require 'thor'
require 'fileutils'
require 'cfnvpn/log'

module CfnVpn
  class Associations < Thor::Group
    include Thor::Actions
    include CfnVpn::Log

    argument :name

    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    def set_loglevel
      Log.logger.level = Logger::DEBUG if @options['verbose']
    end

    def stack_exist
      @deployer = CfnVpn::Deployer.new(@options['region'],@name)
      if !@deployer.does_cf_stack_exist()
        Log.logger.error "#{@name}-cfnvpn stack doesn't exists in this account and region #{@options['region']}"
        exit 1
      end
    end

    def associated?
      @associated = @deployer.get_parameter_value('AssociateSubnets')
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
