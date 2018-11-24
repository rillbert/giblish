require "test_helper"
require "pathname"
require "fileutils"

require_relative "../lib/giblish.rb"

class RunGiblishTest < Minitest::Test

  def setup
    @src_dir = Pathname.new "./data/testdocs/wellformed/"
    @dst_dir = Pathname.new "testoutput"
    @logging = "--log-level info"
  end

  def teardown
    FileUtils.remove_dir(@dst_dir) if @dst_dir.directory?
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
    g = `lib/giblish.rb #{@logging} #{@src_dir.to_s} #{@dst_dir.to_s}`
    assert_equal 0, $?.exitstatus
    assert_match(/Giblish is done!$/, g)
  end

  def test_basic_pdf_conversion
    g = `lib/giblish.rb -f pdf -d #{@logging} #{@src_dir.to_s} #{@dst_dir.to_s}`
    assert_equal 0, $?.exitstatus
    assert_match(/Giblish is done!$/, g)
  end

  def test_basic_docid_resolution_html
    g = `lib/giblish.rb -d #{@logging} #{@src_dir.join("docidtest").to_s} #{@dst_dir.to_s}`
    assert_equal 0, $?.exitstatus
    assert_match(/Giblish is done!$/, g)
  end

  def test_basic_docid_resolution_pdf
    g = `lib/giblish.rb -f pdf -d #{@logging} #{@src_dir.join("docidtest").to_s} #{@dst_dir.to_s}`
    assert_equal 0, $?.exitstatus
    assert_match(/Giblish is done!$/, g)
  end
end
