require_relative "test_helper"
require_relative "../lib/giblish/treeconverter"
require_relative "../lib/giblish/pathtree"

module Giblish
  class TreeConverterTest < Minitest::Test
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

    # helper class that gets the adoc source from the given file
    class AdocFromFile
      def initialize(tree_node)
        @node = tree_node
      end

      def adoc_source
        File.read(@node.pathname)
      end
    end

    def test_generate_html
      TmpDocDir.open do |tmp_docs|
        file_1 = tmp_docs.add_doc_from_str(create_doc_str("File 1", "D-001"), "src")
        file_2 = tmp_docs.add_doc_from_str(create_doc_str("File 2", "D-002"), "src")
        file_3 = tmp_docs.add_doc_from_str(create_doc_str("File 3", "D-004"), "src/subdir")

        p = Pathname.new(tmp_docs.dir)
        src_tree = PathTree.build_from_fs(p / "src", prune: false) do |pt|
          !pt.directory? && pt.extname == ".adoc"
        end
        src_tree.traverse_preorder do |level, n|
          next unless n.leaf?

          n.data = AdocFromFile.new(n)
        end

        assert_equal(3, src_tree.leave_pathnames.count)
        tc = TreeConverter.new(
          src_tree.node(p / "src", from_root: true),
          p / "dst",
          {
            adoc_api_opts: {
              standalone: false
            },
            adoc_doc_attribs: {}
          }
        )
        tc.run

        # assert that there now are 3 html files
        dt = tc.dst_tree
        assert_equal(3, dt.leave_pathnames.count)
        dt.leave_pathnames.each { |p| assert_equal(".html", p.extname) }
      end
    end

    # helper class that gets the adoc source from the string given
    # at instantiation.
    class AdocFromString
      attr_reader :adoc_source

      def initialize(adoc_source)
        @adoc_source = adoc_source
      end
    end

    def test_generate_meta_docs
      TmpDocDir.open do |tmp_docs|
        p = Pathname.new(tmp_docs.dir)
        src_tree = PathTree.new(p / "src/metafile_1",
          AdocFromString.new(<<~A_SRC
            = Source 1
            :toc: left

            == Paragraph 1

            bla bla
          A_SRC
                            ))

        assert_equal(1, src_tree.leave_pathnames.count)
        tc = TreeConverter.new(
          src_tree.node(p / "src", from_root: true),
          p / "dst",
          {
            adoc_api_opts: {
              standalone: false
            },
            adoc_doc_attribs: {}
          }
        )
        tc.run

        # assert that there is 1 html file
        dt = tc.dst_tree
        assert_equal(1, dt.leave_pathnames.count)
        assert_equal(p / "dst/metafile_1.html", dt.leave_pathnames[0])
      end
    end
  end
end
