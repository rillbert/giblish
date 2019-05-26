require "fileutils"
require "test_helper"
require_relative "../lib/giblish/utils.rb"
require_relative "../lib/giblish/docid.rb"

class DepGraphTests < Minitest::Test
  include Giblish::TestUtils

  def setup
    @src_root = "#{File.expand_path(File.dirname(__FILE__))}/../data/testdocs"
    setup_log_and_paths
  end

  def teardown
    teardown_log_and_paths dry_run: false
  end

  def test_graph_is_created_depending_on_graphviz
    args = ["--log-level",
            "info",
            "--resolve-docid",
            @src_root + "/wellformed/docidtest",
            @dst_root]
    status = Giblish.application.run_with_args args
    assert_equal 0, status

    if Giblish::which("dot")
      assert (File.exist? @dst_root+"/graph.html")
    elsif
      assert (!File.exist? @dst_root+"/graph.html")
    end
    assert (File.exist? @dst_root+"/index.html")
    assert (!File.exist? @dst_root+"/docdeps.svg")
  end

  def test_graph_is_not_created_without_option
    args = ["--log-level",
            "info",
            @src_root + "/wellformed/docidtest",
            @dst_root]
    status = Giblish.application.run_with_args args
    assert_equal 0, status
    assert (!File.exist? @dst_root+"/graph.html")
    assert (File.exist? @dst_root+"/index.html")
    assert (!File.exist? @dst_root+"/docdeps.svg")
  end
end
