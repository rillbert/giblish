require_relative "../test_helper"
require_relative "../../lib/giblish"

module Giblish
  # tests the basic functionality of giblish as run via a terminal
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

    def test_w_r_s_combos
      TmpDocDir.open(preserve: false) do |tmp_docs|
        topdir = tmp_docs.dir
        `lib/giblish.rb -w my/css/sheet.css data/testdocs/wellformed #{topdir}`
        assert_equal 0, $?.exitstatus

        `lib/giblish.rb -f pdf -w my/css/sheet.css data/testdocs/wellformed #{topdir}`
        assert_equal 1, $?.exitstatus

        `lib/giblish.rb -f html -w my/css/sheet.css -s mystyle data/testdocs/wellformed #{topdir}`
        assert_equal 1, $?.exitstatus

        `lib/giblish.rb -f html -s mystyle data/testdocs/wellformed #{topdir}`
        assert_equal 1, $?.exitstatus

        `lib/giblish.rb -f html -r my/resource data/testdocs/wellformed #{topdir}`
        assert_equal 1, $?.exitstatus
      end
    end

    def test_hello_world
      TmpDocDir.open(preserve: false) do |tmp_docs|
        topdir = tmp_docs.dir
        `lib/giblish.rb -f html data/testdocs/wellformed #{topdir}`
        assert_equal 0, $?.exitstatus
      end
    end

    def test_hello_world_pdf
      TmpDocDir.open(preserve: false) do |tmp_docs|
        topdir = tmp_docs.dir
        puts `lib/giblish.rb -f pdf data/testdocs/wellformed #{topdir}`
        assert_equal 0, $?.exitstatus
      end
    end

    def test_hello_world_pdf_custom_style
      TmpDocDir.open(preserve: false) do |tmp_docs|
        topdir = tmp_docs.dir
        `lib/giblish.rb -f pdf -r data/resources -s giblish data/testdocs/wellformed #{topdir}`
        assert_equal 0, $?.exitstatus
      end
    end
  end
end
