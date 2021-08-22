require_relative "../test_helper"
require_relative "../../lib/giblish"

module Giblish
  # tests the basic functionality of the Application class
  class ApplicationTest < Minitest::Test
    include Giblish::TestUtils

    ADOC_STR = <<~HELLO_WORLD
      = Hello World

      == Section 1

      A paragraph.
    HELLO_WORLD

    def setup
      # setup logging
      Giblog.setup
    end

    def test_get_help_and_version_msg
      g = `lib/giblish.rb -h`
      assert_equal 0, $?.exitstatus
      assert_match(/^Usage/, g)
  
      g = `lib/giblish.rb -v`
      assert_equal 0, $?.exitstatus
      assert_match(/^Giblish v/, g)
    end
    
    def test_hello_world
      TmpDocDir.open(preserve: false) do |tmp_docs|
        # run the most basic conversion
        tmp_docs.add_doc_from_str(ADOC_STR)
        args = [tmp_docs.dir, tmp_docs.dir]
        Giblish.application.run args

        # check that there are two html files where one is an index
        result_tree = PathTree.build_from_fs(tmp_docs.dir) { |p| p.extname == ".html" }
        assert_equal(2, result_tree.leave_pathnames.count)
        assert(!result_tree.node(Pathname.new(tmp_docs.dir) / "index.html", from_root: true).nil?)

        # check some basic stuff in the generated html files
        tmp_docs.get_html_dom(result_tree) do |node, dom|
          next if !node.leaf? || /index.html$/ =~ node.pathname.to_s

          nof_headers = 0
          dom.xpath("//h1").each do |title|
            nof_headers += 1
            assert_equal("Hello World", title.text)
          end
          assert_equal(1, nof_headers)
        end
      end
    end

    def test_hello_world_pdf
      TmpDocDir.open(preserve: true) do |tmp_docs|
        # run the most basic conversion
        tmp_docs.add_doc_from_str(ADOC_STR)
        args = ["-f", "pdf", tmp_docs.dir, tmp_docs.dir]
        Giblish.application.run args

        # check that there are two pdf files where one is an index
        result_tree = PathTree.build_from_fs(tmp_docs.dir) { |p| p.extname == ".pdf" }
        assert_equal(2, result_tree.leave_pathnames.count)
        assert(!result_tree.node(Pathname.new(tmp_docs.dir) / "index.pdf", from_root: true).nil?)
      end
    end
  end
end
