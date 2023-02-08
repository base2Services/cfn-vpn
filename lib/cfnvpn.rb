require 'thor'
require 'cfnvpn/version'
require 'cfnvpn/init'
require 'cfnvpn/modify'
require 'cfnvpn/config'
require 'cfnvpn/client'
require 'cfnvpn/revoke'
require 'cfnvpn/sessions'
require 'cfnvpn/routes'
require 'cfnvpn/share'
require 'cfnvpn/embedded'
require 'cfnvpn/renew_certificate'

module CfnVpn
  class Cli < Thor

    map %w[--version -v] => :__print_version
    desc "--version, -v", "print the version"
    def __print_version
      puts CfnVpn::VERSION
    end

    register CfnVpn::Init, 'init', 'init [name]', 'Create a AWS Client VPN'
    tasks["init"].options = CfnVpn::Init.class_options
    
    register CfnVpn::RenewCertificate, 'renew', 'renew [name]', 'Create a AWS Client VPN'
    tasks["renew"].options = CfnVpn::RenewCertificate.class_options

    register CfnVpn::Modify, 'modify', 'modify [name]', 'Modify your AWS Client VPN'
    tasks["modify"].options = CfnVpn::Modify.class_options

    register CfnVpn::Config, 'config', 'config [name]', 'Retrieve the config for the AWS Client VPN'
    tasks["config"].options = CfnVpn::Config.class_options

    register CfnVpn::Client, 'client', 'client [name]', 'Create a new client certificate'
    tasks["client"].options = CfnVpn::Client.class_options

    register CfnVpn::Revoke, 'revoke', 'revoke [name]', 'Revoke a client certificate'
    tasks["revoke"].options = CfnVpn::Revoke.class_options

    register CfnVpn::Sessions, 'sessions', 'sessions [name]', 'List and kill current vpn connections'
    tasks["sessions"].options = CfnVpn::Sessions.class_options

    register CfnVpn::Routes, 'routes', 'routes [name]', 'List, add or delete client vpn routes'
    tasks["routes"].options = CfnVpn::Routes.class_options

    register CfnVpn::Share, 'share', 'share [name]', 'Provide a user with a s3 signed download for certificates and config'
    tasks["share"].options = CfnVpn::Share.class_options

    register CfnVpn::Embedded, 'embedded', 'embedded [name]', 'Embed client certs into config and generate S3 presigned URL'
    tasks["embedded"].options = CfnVpn::Embedded.class_options

  end
end
