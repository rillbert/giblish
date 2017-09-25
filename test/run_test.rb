require "test_helper"

require_relative "../lib/giblish.rb"

class RunGiblishTest < Minitest::Test
  def test_get_help_and_version_msg
    g = `lib/giblish.rb -h`
    assert_equal 0, $?.exitstatus
    assert_match(/^Usage/, g)

    g = `lib/giblish.rb -v`
    assert_equal 0, $?.exitstatus
    assert_match(/^Giblish v/, g)
  end

  def test_basic_html_conversion
    g = `lib/giblish.rb --log-level info ./data/testdocs/wellformed/ testoutput`
    assert_equal 0, $?.exitstatus
    assert_match(/Giblish is done!$/, g)
  end

  def test_basic_pdf_conversion
    g = `lib/giblish.rb -f pdf --log-level info ./data/testdocs/wellformed/ testoutput`
    assert_equal 0, $?.exitstatus
    assert_match(/Giblish is done!$/, g)
  end

  def test_basic_docid_resolution
    g = `lib/giblish.rb -d --log-level debug ./data/testdocs/wellformed/docidtest testoutput`
    puts g
    assert_equal 0, $?.exitstatus
    assert_match(/Giblish is done!$/, g)
  end
end
