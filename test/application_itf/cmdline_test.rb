require "logger"
require_relative "../../lib/giblish/cmdline"
require_relative "../test_helper"

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

    def test_invalid_combos
      assert_raises(OptionParser::InvalidArgument) {
        CmdLine.new.parse(%w[--server-search-path hejhopp src dst])
      }

      assert_raises(OptionParser::InvalidArgument) {
        CmdLine.new.parse(%w[--make-searchable -f pdf src dst])
      }
    end

    def test_log_level
      cmdline = CmdLine.new.parse(%w[-f pdf --log-level warn . .])
      assert_equal(Logger::WARN, cmdline.log_level)
    end

    def test_format
      cmdline = CmdLine.new.parse(%w[-f pdf . .])
      assert_equal("pdf", cmdline.format)

      cmdline = CmdLine.new.parse(%w[-f html . .])
      assert_equal("html", cmdline.format)
    end
  end
end
