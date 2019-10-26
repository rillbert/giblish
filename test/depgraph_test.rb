require "fileutils"
require "test_helper"
require_relative "../lib/giblish/utils.rb"
require_relative "../lib/giblish/docid.rb"

class DepGraphTests < Minitest::Test
  include Giblish::TestUtils

  def setup
    # setup logging
    Giblog.setup
  end

  def test_graph_is_created_depending_on_graphviz
    TmpDocDir.open() do |tmp_docs|
      src_top = tmp_docs.dir + "/src_top"
      dst_top = tmp_docs.dir + "/dst_top"
      copy_test_docs_to_dir src_top

      args = ["--log-level", "info",
              "--resolve-docid",
              src_top + "/wellformed/docidtest",
              dst_top]
      status = Giblish.application.run_with_args args
      assert_equal 0, status

      if Giblish::which("dot")
        assert (File.exist? dst_top + "/graph.html")
      elsif
        assert (!File.exist? dst_top + "/graph.html")
      end

      assert (File.exist? dst_top + "/index.html")
      assert (!File.exist? dst_top + "/docdeps.svg")
    end
  end

  def test_graph_is_not_created_without_option
    TmpDocDir.open() do |tmp_docs|
      src_top = tmp_docs.dir + "/src_top"
      dst_top = tmp_docs.dir + "/dst_top"
      copy_test_docs_to_dir src_top

      args = ["--log-level", "info",
              src_top + "/wellformed/docidtest",
              dst_top]
      status = Giblish.application.run_with_args args
      assert_equal 0, status

      assert (!File.exist? dst_top + "/graph.html")
      assert (File.exist? dst_top + "/index.html")
      assert (!File.exist? dst_top + "/docdeps.svg")
    end
  end
end
