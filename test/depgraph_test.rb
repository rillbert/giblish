require "fileutils"
require "test_helper"
require_relative "../lib/giblish/utils.rb"
require_relative "../lib/giblish/docid.rb"

class DepGraphTests < Minitest::Test
  def setup
    # setup logging
    Giblog.setup

    # find test directory path
    @testdir_path = File.expand_path(File.dirname(__FILE__))

    @src_root = "#{@testdir_path}/../data/testdocs"
    @dst_root = "#{@testdir_path}/../testoutput"
    FileUtils.mkdir_p @dst_root

    # Instanciate a path manager with
    # source root ==  .../giblish/data/testdocs and
    # destination root == .../giblish/test/testoutput
    @paths = Giblish::PathManager.new(@src_root,
                                      @dst_root)
  end

  def teardown
    FileUtils.rm_r @dst_root
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
