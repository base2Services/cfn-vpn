require 'thor'
require 'cfnvpn/log'
require 'cfnvpn/s3'
require 'cfnvpn/globals'

module CfnVpn::Actions
  class Routes < Thor::Group
    include Thor::Actions

    argument :name

    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :cidr, desc: 'cidr range'
    class_option :dns, desc: 'dns record to auto lookup ip'
    class_option :subnet, desc: 'the target vpc subnet to route through, if none is supplied the default subnet is used'
    class_option :desc, desc: 'description of the route'

    class_option :groups, type: :array, desc: 'override all authorised groups on thr route'
    class_option :add_groups, type: :array, desc: 'add authorised groups to an existing route'
    class_option :del_groups, type: :array, desc: 'remove authorised groups from an existing route'

    class_option :delete, type: :boolean, desc: 'delete the route from the client vpn'

    def self.source_root
      File.dirname(__FILE__)
    end

    def set_loglevel
      CfnVpn::Log.logger.level = Logger::DEBUG if @options['verbose']
    end

    def set_config
      @config = CfnVpn::Config.get_config(@options[:region], @name)

      if @options[:cidr] && @options[:dns]
        CfnVpn::Log.logger.error "only one of --dns or --cidr can be set"
        exit 1
      end

      if @options[:dns]
        if @options[:dns].include?("*")
          CfnVpn::Log.logger.error("wild card DNS resolution is not supported, use a record that will be resolved by the wild card instead")
          exit 1
        end
        @route = @config[:routes].detect {|route| route[:dns] == @options[:dns]}      
      elsif @options[:cidr]
        @route = @config[:routes].detect {|route| route[:cidr] == @options[:cidr]}      
      end
    end

    def set_route
      @skip_update = false
      @dns_route_cleanup = nil
      if @route && @options[:delete]
        if @options[:dns]
          CfnVpn::Log.logger.info "deleting auto lookup route for endpoint #{@options[:dns]}"
          @config[:routes].reject! {|route| route[:dns] == @options[:dns]}
          @dns_route_cleanup = @options[:dns]
        elsif @options[:cidr]
          CfnVpn::Log.logger.info "deleting route #{@options[:cidr]}"
          @config[:routes].reject! {|route| route[:cidr] == @options[:cidr]}
        end
      elsif @route
        CfnVpn::Log.logger.info "existing route for #{@options[:cidr] ? @options[:cidr] : @options[:dns]} found"
        if @options[:groups]
          CfnVpn::Log.logger.info "replacing groups #{@route[:groups]} with new #{@options[:groups]} for route authorization rule"
          @route[:groups] = @options[:groups]
        end

        if @options[:add_groups]
          CfnVpn::Log.logger.info "adding new group(s) #{@options[:add_groups]} to route authorization rule" 
          @route[:groups].concat(@options[:add_groups]).uniq!
        end

        if @options[:del_groups]
          CfnVpn::Log.logger.info "removing new group(s) #{@options[:del_groups]} to route authorization rule" 
          @route[:groups].reject! {|group| @options[:del_groups].include? group}
        end

        if @options[:desc]
          CfnVpn::Log.logger.warn "description for this route cannot be updated in place. To alter delete the route and add with the new description"
        end

        if @options[:subnet]
          CfnVpn::Log.logger.warn "the target subnet for this route cannot be updated in place. To alter delete the route and add with the new target subnet"
        end
      elsif !@route && @options[:cidr]
        CfnVpn::Log.logger.info "adding new route for #{@options[:cidr]}"
        @config[:routes] << {
          cidr: @options[:cidr],
          desc: @options.fetch(:desc, ""),
          subnet: @options.fetch(:subnet, @config[:subnet_ids].first),
          groups: @options.fetch(@options[:groups], []) + @options.fetch(@options[:add_groups], [])
        }
      elsif !@route && @options[:dns]
        CfnVpn::Log.logger.info "adding new route lookup for dns record #{@options[:dns]}"
        @config[:routes] << {
          dns: @options[:dns],
          desc: @options.fetch(:desc, ""),
          subnet: @options.fetch(:subnet, @config[:subnet_ids].first),
          groups: @options.fetch(@options[:groups], []) + @options.fetch(@options[:add_groups], [])
        }
      else
        @skip_update = true
      end

      CfnVpn::Log.logger.debug "CONFIG: #{@config}"
    end

    def create_bucket_if_bucket_not_set
      if !@config.has_key?(:bucket)
        CfnVpn::Log.logger.error "no bucket found in the config, run the cfn-vpn modify #{name} command to add a bucket"
        exit 1
      end
    end

    def deploy_vpn
      unless @skip_update
        compiler = CfnVpn::Compiler.new(@name, @config)
        template_body = compiler.compile
        CfnVpn::Log.logger.info "Creating cloudformation changeset for stack #{@name}-cfnvpn in #{@options['region']}"
        @deployer = CfnVpn::Deployer.new(@options['region'],@name)
        change_set, change_set_type = @deployer.create_change_set(template_body: template_body)
        @deployer.wait_for_changeset(change_set.id)
        changeset_response = @deployer.get_change_set(change_set.id)

        changes = {"Add" => [], "Modify" => [], "Remove" => []}
        change_colours = {"Add" => "green", "Modify" => 'yellow', "Remove" => 'red'}

        changeset_response.changes.each do |change|
          action = change.resource_change.action
          changes[action].push([
            change.resource_change.logical_resource_id,
            change.resource_change.resource_type,
            change.resource_change.replacement ? change.resource_change.replacement : 'N/A',
            change.resource_change.details.collect {|detail| detail.target.name }.join(' , ')
          ])
        end

        changes.each do |type, rows|
          next if !rows.any?
          puts "\n"
          table = Terminal::Table.new(
            :title => type,
            :headings => ['Logical Resource Id', 'Resource Type', 'Replacement', 'Changes'],
            :rows => rows)
          puts table.to_s.send(change_colours[type])
        end

        CfnVpn::Log.logger.info "Cloudformation changeset changes:"
        puts "\n"
        continue = yes? "Continue?", :green
        if !continue
          CfnVpn::Log.logger.info("Cancelled cfn-vpn modifiy #{@name}")
          exit 1
        end

        @deployer.execute_change_set(change_set.id)
        @deployer.wait_for_execute(change_set_type)
        CfnVpn::Log.logger.info "Changeset #{change_set_type} complete"
      end
    end

    def cleanup_dns_routes
      @vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
      unless @dns_route_cleanup.nil?
        routes = @vpn.get_routes()
        CfnVpn::Log.logger.info("Cleaning up expired routes for #{@dns_route_cleanup}")
        expired_routes = routes.select {|route| route.description.include?(@dns_route_cleanup) }
        expired_routes.each do |route|
          @vpn.delete_route(route.destination_cidr, route.target_subnet)
          @vpn.revoke_auth(route.destination_cidr)
        end
      end
    end

    def get_routes
      @endpoint = @vpn.get_endpoint_id()
      @routes = @vpn.get_routes()
    end

    def display_routes
      rows = @routes.collect do |s|
        groups = @vpn.get_groups_for_route(@endpoint, s.destination_cidr)
        [ s.destination_cidr, s.description, s.status.code, s.target_subnet, s.type, s.origin, (!groups.join("").empty? ? groups.join(' ') : 'AllowAll') ]
      end
      table = Terminal::Table.new(
        :headings => ['Route', 'Description', 'Status', 'Target', 'Type', 'Origin', 'Groups'],
        :rows => rows)
      puts table
    end

  end
end
