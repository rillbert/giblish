require_relative "../test_helper"
require_relative "../../lib/giblish/treeconverter"
require_relative "../../lib/giblish/docid/docid"
require_relative "../../lib/giblish/pathtree"

module Giblish
  class DocidTest < Minitest::Test
    include Giblish::TestUtils

    def setup
      # setup logging
      Giblog.setup
    end

    def teardown
      # need to unregister the docid extension between subsequent tests
      Asciidoctor::Extensions.unregister_all
    end

    def tree_from_src_dir(top_dir)
      src_tree = PathTree.build_from_fs(top_dir, prune: false) do |pt|
        !pt.directory? && pt.extname == ".adoc"
      end
      src_tree.traverse_preorder do |level, n|
        next unless n.leaf?

        n.data = SrcFromFile.new
      end
      src_tree
    end

    def test_build_docid_cache
      TmpDocDir.open(test_data_subdir: "src_top") do |tmp_docs|
        srcdir = Pathname.new(tmp_docs.dir) / "src"
        dstdir = Pathname.new(tmp_docs.dir) / "dst"

        tmp_docs.create_adoc_src_on_disk(srcdir,
          {header: ":docid: D-001"},
          {header: ":docid: D-002"},
          {header: ":docid: D-004", subdir: "subdir"})
        src_tree = PathTree.build_from_fs(srcdir, prune: false)

        # Create a docid preprocessor and register it with a TreeConverter
        d_pp = DocIdExtension::DocidPreBuilder.new
        tc = TreeConverter.new(src_tree, dstdir,
          {
            pre_builders: d_pp,
            adoc_extensions: {
              preprocessor: DocIdExtension::DocidProcessor.new({id_2_node: d_pp.id_2_node})
            }
          })

        # run the tree converter prebuild step that will populate
        # the docid cache
        tc.pre_build(false)

        assert_equal(3, d_pp.cache.keys.count)
        ["D-001", "D-002", "D-004"].each { |id| assert(d_pp.cache.key?(id)) }
      end
    end

    def test_parse_docid_refs
      TmpDocDir.open(preserve: false) do |tmp_docs|
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

        # Create a docid preprocessor and register it with all future TreeConverters
        d_pp = DocIdExtension::DocidPreBuilder.new
        tc = TreeConverter.new(src_tree, dstdir,
          {
            pre_builders: d_pp
          })

        # must register explicitly since we don't call tc.run
        TreeConverter.register_adoc_extensions(
          {preprocessor: DocIdExtension::DocidProcessor.new({id_2_node: d_pp.id_2_node})}
        )

        # run the tree converter prebuild step that will populate
        # the docid cache
        tc.pre_build(false)

        # assert that all the docs' docids have been cached
        assert_equal(3, d_pp.cache.keys.count)
        ["D-001", "D-002", "D-003"].each { |id| assert(d_pp.cache.key?(id)) }

        # run the build step -> will replace the :docid: with resolved :xref:
        # references before generating html
        tc.build

        # TODO: find a check that is not brittle...
        # assert that the expected xrefs have been converted to correct html
        # tmp_docs.get_html_dom(tc.dst_tree) do |n, document|
        #   ref_links = document.xpath("html/body/div/div/div/div/p/a")
        #   assert_equal 2, ref_links.count
        #   # <a href="gib_tst_20210701-141554-7v2eqx.html">D-002</a>

        #   ref_links.each do |ref|
        #     # assert_equal "stylesheet", ref.get("rel")
        #     assert_equal "gib_tst_20210701-141554-7v2eqx.html",
        #       ref.get("href")
        #   end
        # end
      end
    end
  end
end
