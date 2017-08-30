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
    g = `lib/giblish.rb --log-level debug ./data/testdocs/wellformed/ testoutput`
    puts g
    assert_equal 0, $?.exitstatus
    assert_match(/^Giblish v/, g)
  end
end
