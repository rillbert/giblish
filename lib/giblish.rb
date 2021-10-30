#!/usr/bin/env ruby
if /^2/.match?(RUBY_VERSION)
  # suppress warnings for 'experimental' pattern matching
  # for ruby versions < 3.x
  require "warning"
  Warning.ignore(/Pattern matching/)
end

require_relative "giblish/version"
require_relative "giblish/application"
require_relative "giblish/search/request_manager"

module Giblish
  # The main entry point to the giblish application
  class << self
    def application
      @application ||= Giblish::EntryPoint
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  Giblish.application.run_from_cmd_line
end
