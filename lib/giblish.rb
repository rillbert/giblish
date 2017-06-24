#!/usr/bin/env ruby

require_relative "giblish/version"
require_relative "giblish/utils"
require_relative "giblish/core"
require_relative "giblish/buildindex"
require_relative "giblish/cmdline"
require_relative "giblish/pathtree"
require_relative "giblish/application"

module Giblish
  class << self

    def application
      @application ||= Giblish::Application.new
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  Giblish.application.run
end
