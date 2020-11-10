require 'cfnvpn/log'
require 'cfnvpn/templates/vpn'

module CfnVpn
  class Compiler

    def initialize(name, config)
      @name = name
      @config = config
    end

    def compile
      CfnVpn::Log.logger.debug "Compiling cloudformation"
      template = CfnVpn::Templates::Vpn.new()
      template.render(@name, @config)
      CfnVpn::Log.logger.debug "Validating cloudformation"
      valid = template.validate
      CfnVpn::Log.logger.debug "Clouformation Template\n\n#{JSON.parse(valid.to_json).to_yaml}"
      return JSON.parse(valid.to_json).to_yaml
    end

  end
end