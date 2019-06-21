require 'logger'

module CfnVpn
  module Log

    def self.colors
      @colors ||= {
        ERROR: 31, # red
        WARN: 33, # yellow
        INFO: 0,
        DEBUG: 32 # grenn
      }
    end

    def self.logger
      if @logger.nil?
        @logger = Logger.new(STDOUT)
        @logger.level = Logger::INFO
        @logger.formatter = proc do |severity, datetime, progname, msg|
          "\e[#{colors[severity.to_sym]}m#{severity}: - #{msg}\e[0m\n"
        end
      end
      @logger
    end

    def self.logger=(logger)
      @logger = logger
    end

    levels = %w(debug info warn error fatal)
    levels.each do |level|
      define_method("#{level.to_sym}") do |msg|
        self.logger.send(level, msg)
      end
    end

  end
end
