require 'thor'
require 'terminal-table'
require 'cfnvpn/log'
require 'cfnvpn/clientvpn'
require 'cfnvpn/globals'

module CfnVpn::Actions
  class Sessions < Thor::Group
    include Thor::Actions
    include CfnVpn::Log

    argument :name

    class_option :profile, aliases: :p, desc: 'AWS Profile'
    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :kill, desc: 'connection id to kill the connection'

    def self.source_root
      File.dirname(__FILE__)
    end

    def set_loglevel
      logger.level = Logger::DEBUG if @options['verbose']
    end

    def set_directory
      @build_dir = "#{CfnVpn.cfnvpn_path}/#{@name}"
    end

    def get_endpoint
      @vpn = CfnVpn::ClientVpn.new(@name,@options['region'])
      @endpoint_id = @vpn.get_endpoint_id()
    end

    def kill_session
      if !@options['kill'].nil?
        sessions = @vpn.get_sessions(@endpoint_id)
        session = sessions.select { |s| s if s.connection_id  == @options['kill'] }.first
        if session.any? && session.status.code == "active"
          terminate = yes? "Terminate connection #{@options['kill']} for #{session.common_name}?", :yellow
          if terminate
            logger.info "Terminating connection #{@options['kill']} for #{session.common_name}"
            @vpn.kill_session(@endpoint_id,@options['kill'])
          end
        else
          logger.error "Connection id #{@options['kill']} doesn't exist or is not active"
        end
      end
    end

    def display_sessions
      sessions = @vpn.get_sessions(@endpoint_id)
      rows = sessions.collect do |s|
        [ s.common_name, s.connection_established_time, s.status.code, s.client_ip, s.connection_id, s.ingress_bytes, s.egress_bytes ]
      end
      table = Terminal::Table.new(
        :headings => ['Common Name', 'Connected (UTC)', 'Status', 'IP Address', 'Connection ID', 'Ingress Bytes', 'Egress Bytes'],
        :rows => rows)
      puts table
    end

  end
end
