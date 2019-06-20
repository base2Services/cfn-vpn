require 'aws-sdk-cloudformation'
require 'fileutils'
require 'cfnvpn/version'

module CfnVpn
  class Cloudformation

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

    def create_change_set(template_path)
      change_set_name = "#{@stack_name}-#{CfnVpn::CHANGE_SET_VERSION}"
      change_set_type = get_change_set_type()
      template_body = File.read(template_path)

      change_set = @client.create_change_set({
        stack_name: @stack_name,
        template_body: template_body,
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
        change_set_type: change_set_type
      })
      return change_set, change_set_type
    end

    def wait_for_changeset(change_set_id)
      @client.wait_until :change_set_create_complete, change_set_name: change_set_id
    end

    def execute_change_set(change_set_id)
      stack = @client.execute_change_set({
        change_set_name: change_set_id
      })
    end

    def wait_for_execute(change_set_type)
      waiter = change_set_type == 'CREATE' ? :stack_create_complete : :stack_update_complete
      resp = @client.wait_until waiter, stack_name: @stack_name
    end

  end
end
