#!/usr/bin/env ruby
if /^2/.match?(RUBY_VERSION)
  # suppress warnings for 'experimental' pattern matching
  # for ruby versions < 3.x
  require "warning"
  Warning.ignore(/Pattern matching/)
end

require_relative "giblish/version"
require_relative "giblish/utils"
require_relative "giblish/core"
require_relative "giblish/cmdline"
require_relative "giblish/pathtree"
require_relative "giblish/application"

module Giblish
  # The main entry point to the giblish application
  class << self
    def application
      @application ||= Giblish::Application.new
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  Giblish.application.run_from_cmd_line
end
