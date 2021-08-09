require "test_helper"
require "logger"
require_relative "../../lib/giblish/goblish"

module Giblish
  class CmdLineTest < Minitest::Test
    include Giblish::TestUtils

    def test_require_src_dst
      assert_raises(OptionParser::MissingArgument) {
        CmdLine.new.parse(%w[])
      }

      assert_raises(OptionParser::MissingArgument) {
        CmdLine.new.parse(%w[src])
      }

      assert_raises(OptionParser::MissingArgument) {
        CmdLine.new.parse(%w[-f pdf src])
      }
    end

    def test_log_level
      cmdline = CmdLine.new.parse(%w[-f pdf --log-level warn src dst])
      assert_equal(Logger::WARN, cmdline.log_level)
    end
    
    def test_format
      cmdline = CmdLine.new.parse(%w[-f pdf src dst])
      assert_equal("pdf", cmdline.format)

      cmdline = CmdLine.new.parse(%w[-f html src dst])
      assert_equal("html", cmdline.format)
    end
  end
end
