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
        CmdLine.new.parse(%w[--search-assets-deploy hejhopp src dst])
      }

      assert_raises(OptionParser::InvalidArgument) {
        CmdLine.new.parse(%w[--make-searchable -f pdf src dst])
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

    # def test_resource_dir
    #   opts = CmdLine.new.parse(%w[-f html -w http://www.example.com/style.css -r /somewhere/local -s mystyle src dst])

    #   case opts
    #     in web_path: String => wp, style_name: String =>
    #     assert_equal("http://www.example.com/style.css", wp )
    #     in resource_dir: Pathname => r, style_name: String => s
    #     assert(false)
    #   end
    # end
  end
end
