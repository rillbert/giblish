require_relative "../test_helper"
require_relative "../../lib/giblish"

module Giblish
  # tests the basic functionality of the Application class
  class ApplicationTest < Minitest::Test
    include Giblish::TestUtils

    ADOC_STR = <<~HELLO_WORLD
      = Hello World

      == Section 1

      A paragraph.
    HELLO_WORLD

    def setup
      # setup logging
      Giblog.setup
    end

    def test_get_help_and_version_msg
      g = `lib/giblish.rb -h`
      assert_equal 0, $?.exitstatus
      assert_match(/^Usage/, g)
  
      g = `lib/giblish.rb -v`
      assert_equal 0, $?.exitstatus
      assert_match(/^Giblish v/, g)
    end
    
    def test_hello_world
      TmpDocDir.open(preserve: false) do |tmp_docs|
        topdir = tmp_docs.dir
        g = `lib/giblish.rb -f html data/testdocs/wellformed #{topdir}`
        assert_equal 0, $?.exitstatus
      end
    end

    def test_hello_world_pdf
      TmpDocDir.open(preserve: true) do |tmp_docs|
        topdir = tmp_docs.dir
        g = `lib/giblish.rb -f pdf data/testdocs/wellformed #{topdir}`
        assert_equal 0, $?.exitstatus
      end
    end
  end
end
