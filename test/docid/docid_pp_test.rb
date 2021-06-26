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

    def create_doc_str(title, doc_id, refs = nil)
      <<~TST_FILE
        = #{title}
        :toc: left
        :docid: #{doc_id}
        
        == Paragraph
        
        bla bla

        #{refs&.collect { |r| " * Reference to #{r}" }&.join("\n")}

      TST_FILE
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
      TmpDocDir.open(test_data_subdir: "src_top") do |tmp_docs|
        file_1 = tmp_docs.add_doc_from_str(create_doc_str("File 1", "D-001"), "src")
        file_2 = tmp_docs.add_doc_from_str(create_doc_str("File 2", "D-002"), "src")
        file_3 = tmp_docs.add_doc_from_str(create_doc_str("File 3", "D-004"), "src/subdir")

        p = Pathname.new(tmp_docs.dir)
        src_tree = PathTree.build_from_fs(p / "src", prune: false) do |pt|
          !pt.directory? && pt.extname == ".adoc"
        end

        d_pp = DocIdPreprocessor.new
        tc = TreeConverter.new(src_tree, p / "dst",
          {
            pre_builders: d_pp,
            adoc_extensions: {
              preprocessor: d_pp
            }
          }
        )
        tc.pre_build

        tc.build

        assert_equal(3, d_pp.docid_cache.keys.count)
        ["D-001", "D-002", "D-004"].each { |id| assert(d_pp.docid_cache.key?(id)) }
      end
    end
  end
end
