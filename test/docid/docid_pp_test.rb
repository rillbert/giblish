require_relative "../test_helper"
require_relative "../../lib/giblish/treeconverter"
require_relative "../../lib/giblish/docid/preprocessor"
require_relative "../../lib/giblish/pathtree"

module Giblish
  class DocidCollectorTest < Minitest::Test
    include Giblish::TestUtils

    def setup
      # setup logging
      Giblog.setup
    end

    def tree_from_src_dir(top_dir)
      src_tree = PathTree.build_from_fs(top_dir, prune: false) do |pt|
        !pt.directory? && pt.extname == ".adoc"
      end
      src_tree.traverse_preorder do |level, n|
        next unless n.leaf?

        n.data = AdocSrcFromFile.new(n)
      end
      src_tree
    end

    def test_build_docid_cache
      TmpDocDir.open(test_data_subdir: "src_top") do |tmp_docs|
        file_1 = tmp_docs.add_doc_from_str(create_doc_str("File 1", "D-001"), "src")
        file_2 = tmp_docs.add_doc_from_str(create_doc_str("File 2", "D-002"), "src")
        file_3 = tmp_docs.add_doc_from_str(create_doc_str("File 3", "D-004"), "src/subdir")

        p = Pathname.new(tmp_docs.dir)
        src_tree = PathTree.build_from_fs(p / "src", prune: false) do |pt|
          !pt.directory? && pt.extname == ".adoc"
        end

        d_pp = DocIdPreprocessor.new
        tc = TreeConverter.new(src_tree, p / "dst", {pre_builders: d_pp})

        tc.pre_build

        assert_equal(3, d_pp.docid_cache.keys.count)
        ["D-001", "D-002", "D-004"].each { |id| assert(d_pp.docid_cache.key?(id)) }
      end
    end

    def test_parse_docid_refs
      TmpDocDir.open(preserve: true) do |tmp_docs|
        # create three adoc files under .../src and .../src/subdir
        docid = ["D-001", "D-002", "D-003"]
        refs = [["D-002", "D-003"], ["D-001"], ["D-004"]]
        ["src", "src", "src/subdir"].each_with_index do |d, i|
          tmp_docs.add_doc_from_str(CreateAdocDocSrc.new({docid: docid[i]}).add_ref(refs[i]), d)
        end

        # setup a src PathTree from the src_top dir
        p = Pathname.new(tmp_docs.dir)
        fs_root = tree_from_src_dir(p / "src")

        # find the PathTree node pointing to the "src" dir
        st = fs_root.node(p / "src", from_root: true)

        # Create a docid preprocessor and register it with a TreeConverter
        d_pp = DocIdExtension::DocIdCacheBuilder.new
        tc = TreeConverter.new(st, p / "dst",
          {
            pre_builders: d_pp,
            adoc_extensions: {
              preprocessor: DocIdExtension::DocidResolver.new({docid_cache: d_pp})
            }
          })

        # run the tree converter prebuild step that will populate
        # the docid cache
        tc.pre_build

        # assert that all the docs' docids have been cached
        assert_equal(3, d_pp.cache.keys.count)
        docid.each { |id| assert(d_pp.cache.key?(id)) }

        # run the build step -> will replace the :docid: with resolved :xref:
        # references before generating html
        tc.build
      end
    end
  end
end
