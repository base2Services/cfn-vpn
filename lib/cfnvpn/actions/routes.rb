require 'thor'
require 'cfnvpn/log'
require 'cfnvpn/s3'
require 'cfnvpn/globals'

module CfnVpn::Actions
  class Routes < Thor::Group
    include Thor::Actions
    include CfnVpn::Log

    argument :name

    class_option :profile, aliases: :p, desc: 'AWS Profile'
    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :add, desc: 'add cidr to route through the client vpn'
    class_option :del, desc: 'delete cidr route from the client vpn'
    class_option :desc, desc: 'description of the route'

    def self.source_root
      File.dirname(__FILE__)
    end

    def set_loglevel
      Log.logger.level = Logger::DEBUG if @options['verbose']
    end

    def set_directory
      @build_dir = "#{CfnVpn.cfnvpn_path}/#{@name}"
    end

    def add_route
      if !@options['add'].nil?
        if @options['desc'].nil?
          Log.logger.error "--desc option must be provided if adding a new route"
          exit 1
        end

        vpn = CfnVpn::ClientVpn.new(@name,@options['region'])

        if vpn.route_exists?(@options['add'])
          Log.logger.error "route #{@options['add']} already exists in the client vpn"
          exit 1
        end

        Log.logger.info "Adding new route for #{@options['add']}"
        vpn.add_route(@options['add'],@options['desc'])
      end
    end

    def del_route
      if !@options['del'].nil?
        vpn = CfnVpn::ClientVpn.new(@name,@options['region'])

        if !vpn.route_exists?(@options['del'])
          Log.logger.error "route #{@options['del']} doesn't exist in the client vpn"
          exit 1
        end
        delete = yes? "Delete route #{@options['del']}?", :yellow
        if delete
          Log.logger.info "Deleting route for #{@options['del']}"
          vpn.del_route(@options['del'])
        end
      end
    end

    def get_routes
      vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
      @routes = vpn.get_routes()
    end

    def display_routes
      rows = @routes.collect do |s|
        [ s.destination_cidr, s.description, s.status.code, s.target_subnet, s.type, s.origin ]
      end
      table = Terminal::Table.new(
        :headings => ['Route', 'Description', 'Status', 'Target', 'Type', 'Origin'],
        :rows => rows)
      puts table
    end

  end
end
