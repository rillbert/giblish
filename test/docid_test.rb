require "test_helper"
require_relative "../lib/giblish/utils.rb"
require_relative "../lib/giblish/docid.rb"

class DocidCollectorTest < Minitest::Test
  include Giblish::TestUtils

  def setup
    @src_root = "#{File.expand_path(File.dirname(__FILE__))}/../data/testdocs"
    setup_log_and_paths
  end

  def teardown
    teardown_log_and_paths dry_run: false
  end

  def test_collect_docids
    args = ["-d",
            @src_root,
            @dst_root]
    Giblish.application.run_with_args args
    status = Giblish.application.run_with_args args
    assert_equal 0, status
  end
end
