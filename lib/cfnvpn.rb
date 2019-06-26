require 'thor'
require 'cfnvpn/version'
require 'cfnvpn/init'
require 'cfnvpn/modify'
require 'cfnvpn/config'

module CfnVpn
  class Cli < Thor

    map %w[--version -v] => :__print_version
    desc "--version, -v", "print the version"
    def __print_version
      puts CfnVpn::VERSION
    end

    # Initializes ciinabox configuration
    register CfnVpn::Init, 'init', 'init [name]', 'Create a AWS Client VPN'
    tasks["init"].options = CfnVpn::Init.class_options

    register CfnVpn::Modify, 'modify', 'modify [name]', 'Modify your AWS Client VPN'
    tasks["modify"].options = CfnVpn::Modify.class_options

    register CfnVpn::Config, 'config', 'config [name]', 'Retrieve the config for the AWS Client VPN'
    tasks["config"].options = CfnVpn::Config.class_options

  end

  # Aws.config[:retry_limit] = if ENV.key? 'CFNVPN_AWS_RETRY_LIMIT' then (ENV['CFNVPN_AWS_RETRY_LIMIT'].to_i) else 10 end

end
