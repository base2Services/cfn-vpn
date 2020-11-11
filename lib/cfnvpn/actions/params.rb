require 'yaml'
require 'cfnvpn/config'
require 'cfnvpn/log'

module CfnVpn::Actions
  class Params < Thor::Group
    include Thor::Actions
    

    argument :name

    class_option :region, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'set log level to debug', type: :boolean

    class_option :dump, type: :boolean, desc: 'dump config to yaml file'
    class_option :diff_yaml, desc: 'diff yaml file with deployed config'

    def self.source_root
      File.dirname(__FILE__)
    end

    def set_loglevel
      CfnVpn::Log.logger.level = Logger::DEBUG if @options['verbose']
    end

    def get_config
      @config = CfnVpn::Config.get_config(@options[:region], @name)
    end

    def dump
      CfnVpn::Config.dump_config_to_yaml_file(name, @config) if @options[:dump]
    end

    def setup_display
      @headings = ['Param', 'Deployed Value']
      @rows = []
    end

    def diff
      if @options[:diff_yaml]
        yaml_params = CfnVpn::Config.get_config_from_yaml_file(@options[:diff_yaml])

        @headings << 'YAML Value'
        @config.each do |key, value|
          row = [key, value]
          if yaml_params.has_key? key
            row << yaml_params[key]
          else
            row << nil
          end

          if row[1] != row[2]
            row[1] = row[1].to_s.red
            row[2] = row[2].to_s.red
          end

          @rows << row
        end
      else
        @rows = @config.to_a
      end
    end

    def display
      table = Terminal::Table.new(
        :title => 'Params',
        :headings => @headings,
        :rows => @rows)
      puts table
    end

  end
end
