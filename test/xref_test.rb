# frozen_string_literal: true

require "oga"
require "test_helper"

module Giblish
  # tests that asciidoc attributes can be set via the -a or
  # --attributes flag at invocation.
  class XrefTest < Minitest::Test
    include Giblish::TestUtils

    def setup
      # setup logging
      Giblog.setup

      # use a template xref doc
      @xref_str = <<~XREF_TEST
        = Test xref handling
        :numbered:

        == My First Section

        This is a ref to <<section_id_2>> via explicit id (it is not possible to use automatic id
        when an explicit id is set).

        [[section_id_2]]
        == My Second Section

        This is a reference to <<_my_first_section>> via automatic id.

        NOTE: This is to test the note-caption attrib
      XREF_TEST
    end

    def test_xref_short_style_via_attrib_flag
      TmpDocDir.open(preserve: false) do |tmp_docs|
        # act on the input data
        adoc_filename = tmp_docs.add_doc_from_str(@xref_str)
        args = ["--log-level", "info",
          "-a", "xrefstyle=short",
          tmp_docs.dir,
          tmp_docs.dir]
        Giblish.application.run args

        result = PathTree.build_from_fs(tmp_docs.dir) { |p| p.extname == ".html" && p.basename.to_s != "index.html" }
        assert_equal(1, result.leave_pathnames.count)

        expected_ref_text = ["Section 2", "Section 1"]
        tmp_docs.get_html_dom(result) do |node, dom|
          next if /index.html$/.match?(node.pathname.to_s)

          ref_nr = 0
          dom.xpath("//a").each do |el|
            assert_equal(expected_ref_text[ref_nr], el.text)
            ref_nr += 1
          end
        end
      end
    end

    def test_xref_full_style_via_attrib_flag
      TmpDocDir.open(preserve: false) do |tmp_docs|
        tmp_docs.add_doc_from_str(@xref_str)
        args = ["--log-level", "info",
          "-a", "xrefstyle=full",
          tmp_docs.dir,
          tmp_docs.dir]
        Giblish.application.run args

        result = PathTree.build_from_fs(tmp_docs.dir) { |p| p.extname == ".html" && p.basename.to_s != "index.html" }
        assert_equal(1, result.leave_pathnames.count)

        # note the 'smart quotes'...
        expected_ref_text = ["Section 2, “My Second Section”", "Section 1, “My First Section”"]

        tmp_docs.get_html_dom(result) do |node, dom|
          next if /index.html$/.match?(node.pathname.to_s)

          ref_nr = 0
          dom.xpath("//a").each do |el|
            assert_equal(expected_ref_text[ref_nr], el.text)
            ref_nr += 1
          end
        end
      end
    end

    def test_xref_and_note_attrib
      TmpDocDir.open(preserve: false) do |tmp_docs|
        tmp_docs.add_doc_from_str(@xref_str)
        expected_note_text = "TestNote"
        args = ["--log-level", "info",
          "-a", "xrefstyle=full",
          "-a", "note-caption=#{expected_note_text}",
          tmp_docs.dir,
          tmp_docs.dir]
        Giblish.application.run args

        result = PathTree.build_from_fs(tmp_docs.dir) { |p| p.extname == ".html" && p.basename.to_s != "index.html" }
        assert_equal(1, result.leave_pathnames.count)

        # note the 'smart quotes'...
        expected_ref_text = ["Section 2, “My Second Section”", "Section 1, “My First Section”"]

        tmp_docs.get_html_dom(result) do |node, dom|
          next if /index.html$/.match?(node.pathname.to_s)

          ref_nr = 0
          dom.xpath("//a").each do |el|
            assert_equal(expected_ref_text[ref_nr], el.text)
            ref_nr += 1
          end

          dom.css(".title").each do |n|
            assert_equal expected_note_text, n.text
          end
        end
      end
    end
  end
end
