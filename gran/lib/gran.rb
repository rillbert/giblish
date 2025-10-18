# frozen_string_literal: true

require_relative "gran/version"
require_relative "gran/loggable"
require_relative "gran/pathtree"
require_relative "gran/tree_transformer"

module Gran
  class Error < StandardError; end

  #
  # Setup the logger object for the module.
  #
  # Users of the module can assign a logger object to the module.
  # If no logger object is assigned, a default logger object
  # based on the Ruby Logger class is created.
  #
  class << self
    # @return [logger] set the logger object for the module
    attr_writer :logger

    #
    # Used to access the logger for the module.
    #
    # @return [logger] the logger object for the module
    #
    def logger
      @logger ||= default_logger
    end

    private

    #
    # Implement a default logger for the module.
    #
    # @return [logger] the default logger object for the module
    #
    def default_logger
      require "logger"
      Logger.new($stdout).tap do |log|
        log.progname = name
      end
    end
  end
end
