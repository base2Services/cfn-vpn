require 'cfhighlander.publisher'
require 'cfhighlander.factory'
require 'cfhighlander.validator'

require 'cfnvpn/version'

module CfnVpn
  class CfHiglander

    def initialize(region, name, config, output_dir)
      @component_name = name
      @region = region
      @config = config
      @cfn_output_format = 'yaml'
      ENV['CFHIGHLANDER_WORKDIR'] = output_dir
    end

    def render()
      component = load_component(@component_name)
      compiled = compile_component(component)
      validate_component(component,compiled.cfn_template_paths)
      cfn_template_paths = compiled.cfn_template_paths
      return cfn_template_paths.select { |path| path.match(@component_name) }.first
    end

    private

    def load_component(component_name)
      factory = Cfhighlander::Factory::ComponentFactory.new
      component = factory.loadComponentFromTemplate(component_name)
      component.config = @config
      component.version = CfnVpn::VERSION
      component.load()
      return component
    end

    def compile_component(component)
      component_compiler = Cfhighlander::Compiler::ComponentCompiler.new(component)
      component_compiler.compileCloudFormation(@cfn_output_format)
      return component_compiler
    end

    def validate_component(component,template_paths)
      component_validator = Cfhighlander::Cloudformation::Validator.new(component)
      component_validator.validate(template_paths, @cfn_output_format)
    end

  end
end
