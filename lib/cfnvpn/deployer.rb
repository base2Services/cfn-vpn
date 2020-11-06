require 'aws-sdk-cloudformation'
require 'fileutils'
require 'cfnvpn/version'
require 'cfnvpn/log'
require 'cfnvpn/string'

module CfnVpn
  class Deployer
    include CfnVpn::Log

    def initialize(region,name)
      @name = name
      @stack_name = "#{@name}-cfnvpn"
      @client = Aws::CloudFormation::Client.new(region: region)
    end

    # TODO: check for REVIEW_IN_PROGRESS
    def does_cf_stack_exist()
      begin
        resp = @client.describe_stacks({
          stack_name: @stack_name,
        })
      rescue Aws::CloudFormation::Errors::ValidationError
        return false
      end
      return resp.size > 0
    end

    def get_change_set_type()
      return does_cf_stack_exist() ? 'UPDATE' : 'CREATE'
    end

    def create_change_set(template_body: nil, parameters: {})
      change_set_name = "#{@stack_name}-#{CfnVpn::CHANGE_SET_VERSION}-#{Time.now.utc.strftime("%Y%m%d%H%M%S")}"
      change_set_type = get_change_set_type()

      if change_set_type == 'CREATE'
        params = get_parameters_from_template(template_body)
      else
        params = get_parameters_from_stack()
      end

      params.each do |param|
        if !parameters[param[:parameter_key]].nil?
          param[:parameter_value] = parameters[param[:parameter_key]]
          param[:use_previous_value] = false
        end
      end

      changeset_args = {
        stack_name: @stack_name,
        parameters: params,
        tags: [
          {
            key: "cfnvpn:version",
            value: CfnVpn::VERSION,
          },
          {
            key: "cfnvpn:name",
            value: @name,
          }
        ],
        change_set_name: change_set_name,
        change_set_type: change_set_type,
        capabilities: ['CAPABILITY_IAM']
      }

      if !template_body.nil?
        changeset_args[:template_body] = template_body
      else
        changeset_args[:use_previous_template] = true
      end

      Log.logger.debug "Creating changeset"
      change_set = @client.create_change_set(changeset_args)
      return change_set, change_set_type
    end

    def wait_for_changeset(change_set_id)
      Log.logger.debug "Waiting for changeset to be created"
      begin
        @client.wait_until :change_set_create_complete, change_set_name: change_set_id
      rescue Aws::Waiters::Errors::FailureStateError => e
        change_set = get_change_set(change_set_id)
        Log.logger.error("change set status: #{change_set.status} reason: #{change_set.status_reason}")
        exit 1
      end
    end

    def get_change_set(change_set_id)
      @client.describe_change_set({
        change_set_name: change_set_id,
      })
    end

    def execute_change_set(change_set_id)
      Log.logger.debug "Executing the changeset"
      stack = @client.execute_change_set({
        change_set_name: change_set_id
      })
    end

    def wait_for_execute(change_set_type)
      waiter = change_set_type == 'CREATE' ? :stack_create_complete : :stack_update_complete
      Log.logger.info "Waiting for changeset to #{change_set_type}"
      resp = @client.wait_until waiter, stack_name: @stack_name
    end

    def get_parameters_from_stack()
      resp = @client.get_template_summary({ stack_name: @stack_name })
      return resp.parameters.collect { |p| { parameter_key: p.parameter_key, use_previous_value: true }  }
    end

    def get_parameters_from_template(template_body)
      resp = @client.get_template_summary({ template_body: template_body })
      return resp.parameters.collect { |p| { parameter_key: p.parameter_key, parameter_value: p.default_value }  }
    end

    def get_parameter_value(parameter)
      resp = @client.describe_stacks({ stack_name: @stack_name })
      stack = resp.stacks.first
      parameter = stack.parameters.detect {|p| p.parameter_key == parameter}
      return parameter ? parameter.parameter_value : nil
    end

    def get_outputs_from_stack()
      resp = @client.describe_stacks({
        stack_name: @stack_name,
      })
      stack = resp.stacks.first
      return Hash[stack.outputs.collect {|output| [output.output_key.underscore.to_sym, output.output_value]}]
    end
  end
end
