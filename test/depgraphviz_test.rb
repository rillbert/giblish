require "fileutils"
require "test_helper"
require_relative "../lib/giblish/indexbuilders/depgraphviz"

module Giblish
  class DepGraphVizTest < Minitest::Test
    include Giblish::TestUtils

    TEST_STR_BASIC = <<~DOT_STR
    [graphviz,"docdeps","svg",options="inline"]
    ....
    digraph document_deps {
      bgcolor="#33333310"
      node [shape=note,
            fillcolor="#ebf26680",
            style="filled,solid"
          ]

    rankdir="LR"

    }
    ....

    DOT_STR

    def setup
      # setup logging
      Giblog.setup
    end

    FakeConvInfo = Struct.new(:title, :docid, :dst_rel_path)

    def test_create_graph_source

      info_2_ids = {
        FakeConvInfo.new("Doc 1", "D-1", Pathname.new("my/subdir/file1.html")) => ["D-2", "D-3"],
        FakeConvInfo.new("Doc 2", "D-2", Pathname.new("my/file2.html")) => ["D-1"],
        FakeConvInfo.new("Doc 3", "D-3", Pathname.new("./file3.html")) => []
      }
      dg = DotGraphAdoc.new(info_2_ids)
      puts dg.source
      # assert_equal(TEST_STR_BASIC, dg.source)

    end
  end
end
