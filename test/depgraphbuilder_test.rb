require "fileutils"
require "test_helper"
require_relative "../lib/giblish/indexbuilders/dotdigraphadoc"
require_relative "../lib/giblish/indexbuilders/d3treegraph"
require_relative "../lib/giblish/indexbuilders/depgraphbuilder"

module Giblish
  class DepGraphBuilderTest < Minitest::Test
    include Giblish::TestUtils

    TEST_STR_BASIC = <<~DOT_STR
      [graphviz,target="gibgraph",format="svg",svg-type="inline",cachedir="/my/temp/dir"]
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

    def test_create_dot_digraph
      info_2_ids = {
        FakeConvInfo.new("Doc 1", "D-1", Pathname.new("my/subdir/file1.html")) => ["D-2", "D-3"],
        FakeConvInfo.new("Doc 2", "D-2", Pathname.new("my/file2.html")) => ["D-1"],
        FakeConvInfo.new("Doc 3 - longlonglonglonglonglonglong long title", "D-3", Pathname.new("./file3.html")) => []
      }
      dg = DotDigraphAdoc.new(info_2_ids: info_2_ids,
        opts: {"svg-type" => "inline", "cachedir" => "/my/temp/dir"})
      assert_equal(TEST_STR_BASIC, dg.source)
    end

    class TestTitleDocid
      attr_reader :title, :docid, :src_rel_path
      @@docid = 0
      def initialize(node)
        @title = "T - #{node.segment}"
        @docid = @@docid += 1
        @src_rel_path = Pathname.new("hejsan")
      end
    end

    def test_create_d3_digraph
      # tree = {
      #   FakeConvInfo.new("Doc 1", "D-1", Pathname.new("my/subdir/file1.html")) => ["D-2", "D-3"],
      #   FakeConvInfo.new("Doc 2", "D-2", Pathname.new("my/file2.html")) => ["D-1"],
      #   FakeConvInfo.new("Doc 3 - longlonglonglonglonglonglong long title", "D-3", Pathname.new("./file3.html")) => []
      # }
      t = PathTree.build_from_fs(__dir__, prune: true)
      t.traverse_preorder do |level, node|
        # next unless node.leaf?

        node.data = TestTitleDocid.new(node)
      end
      dg = D3TreeGraph.new(tree: t)
      require "json"
      puts JSON.pretty_generate(dg.tree)

      File.write("testd3.html", dg.source)
      return
      assert_equal(TEST_STR_BASIC, dg.source)
    end

    def test_create_digraph_page
      TmpDocDir.open(preserve: true) do |tmp_docs|
        srcdir = Pathname.new(tmp_docs.dir) / "src"
        dstdir = Pathname.new(tmp_docs.dir) / "dst"

        tmp_docs.create_adoc_src_on_disk(srcdir,
          {header: ":docid: D-001",
           paragraphs: [title: "Section 1", text: "Ref to <<:docid:D-002>> and <<:docid:D-003>>."]},
          {header: ":docid: D-002",
           paragraphs: [title: "Section 1", text: "Ref to <<:docid:D-001>>."]},
          {header: ":docid: D-003",
           paragraphs: [title: "Section 1", text: "Ref to <<:docid:D-004>>."],
           subdir: "subdir"})
        src_tree = PathTree.build_from_fs(srcdir, prune: false)

        src_tree.traverse_preorder do |level, n|
          next unless n.leaf?

          n.data = SrcFromFile.new
        end

        # Instantiate docid and graph processors
        pb = DocIdExtension::DocidPreBuilder.new
        docid_pp = DocIdExtension::DocidProcessor.new({id_2_node: pb.id_2_node})
        dg = DependencyGraphPostBuilder.new(docid_pp.node_2_ids, nil, nil, nil, "graph")

        tc = TreeConverter.new(src_tree, dstdir,
          {
            pre_builders: pb,
            post_builders: dg
          })

        # must register explicitly since we don't call tc.run
        TreeConverter.register_adoc_extensions(
          {preprocessor: docid_pp}
        )

        # run the tree converter prebuild step that will populate
        # the docid cache
        tc.pre_build(abort_on_exc: true)
        tc.build(abort_on_exc: true)
        tc.post_build(abort_on_exc: true)
      end
    end
  end
end
