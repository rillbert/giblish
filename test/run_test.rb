require "test_helper"
require "pathname"
require "fileutils"

require_relative "../lib/giblish.rb"

class RunGiblishTest < Minitest::Test
  include Giblish::TestUtils

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

  def test_basic_html_conversion
    TmpDocDir.open(test_data_subdir: "src_top") do |tmp_docs|
      dst_top = tmp_docs.dir + "/dst_top"

      # act on the input data
      args = ["--log-level", "warn",
              tmp_docs.src_data_top,
              dst_top]
      status = Giblish.application.run args
      assert_equal 0,status
    end

  end

  def test_basic_pdf_conversion
    TmpDocDir.open(test_data_subdir: "src_top") do |tmp_docs|
      dst_top = tmp_docs.dir + "/dst_top"

      # act on the input data
      args = ["--log-level", "warn",
              "-f", "pdf",
              tmp_docs.src_data_top,
              dst_top]

      status = Giblish.application.run args
      assert_equal 0,status
    end
  end
end
