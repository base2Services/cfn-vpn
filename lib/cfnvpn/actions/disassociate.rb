require 'thor'
require 'fileutils'
require 'cfnvpn/log'

module CfnVpn
  class Disassociate < Thor::Group
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

    def disassociated?
      if @deployer.get_parameter_value('AssociateSubnets') == 'false'
        Log.logger.error "Subnets are already disassociated"
        exit 0
      end
    end

    def disassociate
      Log.logger.info "Disassociating subnets ..."
      change_set, change_set_type = @deployer.create_change_set(parameters: {"AssociateSubnets" => 'false'})
      @deployer.wait_for_changeset(change_set.id)
      @deployer.execute_change_set(change_set.id)
      @deployer.wait_for_execute(change_set_type)
      Log.logger.info "Disassociate complete"
    end

  end
end
