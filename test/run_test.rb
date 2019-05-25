require "test_helper"
require "pathname"
require "fileutils"

require_relative "../lib/giblish.rb"

class RunGiblishTest < Minitest::Test
  include Giblish::TestUtils

  def setup
    # create dir for test docs
    @src_root = "#{File.expand_path(File.dirname(__FILE__))}/../data/testdocs/wellformed"
    setup_log_and_paths

    @logging = "info"
  end

  def teardown
    teardown_log_and_paths dry_run: false
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
    # act on the input data
    args = ["--log-level", @logging,
            @src_root.to_s,
            @dst_root.to_s]
    status = Giblish.application.run_with_args args

    # assert expected
    assert_equal 0,status
  end

  def test_basic_pdf_conversion
    # act on the input data
    args = ["--log-level", @logging,
            "-f", "pdf",
            @src_root.to_s,
            @dst_root.to_s]
    status = Giblish.application.run_with_args args

    # assert expected
    assert_equal 0,status
  end

  def test_basic_docid_resolution_html
    # act on the input data
    args = ["--log-level", @logging,
            "-d",
            Pathname.new(@src_root).join("docidtest").to_s,
            @dst_root.to_s]
    status = Giblish.application.run_with_args args

    # assert expected
    assert_equal 0,status
    # g = `lib/giblish.rb -d #{@logging} #{@src_dir.join("docidtest").to_s} #{@dst_dir.to_s}`
    # assert_equal 0, $?.exitstatus
    # assert_match(/Giblish is done!$/, g)
  end

  def test_basic_docid_resolution_pdf
    # act on the input data
    args = ["--log-level", @logging,
            "-d",
            "-f", "pdf",
            Pathname.new(@src_root).join("docidtest").to_s,
            @dst_root.to_s]
    status = Giblish.application.run_with_args args

    # assert expected
    assert_equal 0,status

    # g = `lib/giblish.rb -f pdf -d #{@logging} #{@src_dir.join("docidtest").to_s} #{@dst_dir.to_s}`
    # assert_equal 0, $?.exitstatus
    # assert_match(/Giblish is done!$/, g)
  end
end
