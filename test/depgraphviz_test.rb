require "fileutils"
require "test_helper"
require_relative "../lib/giblish/indexbuilders/depgraphviz"

module Giblish
  class DepGraphVizTest < Minitest::Test
    include Giblish::TestUtils

    TEST_STR_BASIC = <<~DOT_STR
      [graphviz,target="gibgraph",format="svg",svg-type="inline"]
      ....
      digraph document_deps {
        bgcolor="#33333310"
        labeljust=l
        node [shape=note,
              fillcolor="#ebf26680",
              style="filled,solid"
            ]
      
      rankdir="LR"
      
      
      "D-3"[label="D-3
      Doc 3 - longlon-
      glonglonglonglo-
      nglong long
      title", URL="./file3.html" ]
      "D-2"[label="D-2
      Doc 2", URL="my/file2.html" ]
      "D-1"[label="D-1
      Doc 1", URL="my/subdir/file1.html" ]
      "D-1" -> { "D-2" "D-3"}
      "D-2" -> { "D-1"}
      "D-3"
      
      }
      ....

    DOT_STR

    def setup
      # setup logging
      Giblog.setup
    end

    # mockup for a ConversionInfo instance 
    FakeConvInfo = Struct.new(:title, :docid, :dst_rel_path)

    def test_create_graph_source
      info_2_ids = {
        FakeConvInfo.new("Doc 1", "D-1", Pathname.new("my/subdir/file1.html")) => ["D-2", "D-3"],
        FakeConvInfo.new("Doc 2", "D-2", Pathname.new("my/file2.html")) => ["D-1"],
        FakeConvInfo.new("Doc 3 - longlonglonglonglonglonglong long title", "D-3", Pathname.new("./file3.html")) => []
      }
      dg = DotGraphAdoc.new(info_2_ids)
      assert_equal(TEST_STR_BASIC, dg.source)
    end
  end
end
