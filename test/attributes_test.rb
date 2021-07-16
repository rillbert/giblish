# frozen_string_literal: true

require "oga"
require "test_helper"
require_relative "../lib/giblish/utils"
require_relative "../lib/giblish/docid"

# tests that asciidoc attributes can be set via the -a or
# --attributes flag at invocation.
class AttributesTest < Minitest::Test
  include Giblish::TestUtils

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

  def setup
    # setup logging
    Giblog.setup
  end

  def test_xref_short_style_via_attrib_flag
    expected_ref_text = ["Section 2",
      "Section 1"]

    TmpDocDir.open do |tmp_docs|
      # act on the input data
      adoc_filename = tmp_docs.add_doc_from_str @xref_str
      args = ["--log-level", "info",
        "-a", "xrefstyle=short",
        tmp_docs.dir,
        tmp_docs.dir]
      Giblish.application.run args

      # assert that the expected matches the actual
      tmp_docs.check_html_dom adoc_filename do |html_tree|
        ref_nr = 0
        html_tree.css("a").each do |n|
          assert_equal expected_ref_text[ref_nr], n.text
          ref_nr += 1
        end
      end
    end
  end

  def test_xref_full_style_via_attrib_flag
    # note the 'smart quotes'...
    expected_ref_text = ["Section 2, “My Second Section”",
      "Section 1, “My First Section”"]

    TmpDocDir.open do |tmp_docs|
      # act on the input data
      adoc_filename = tmp_docs.add_doc_from_str @xref_str
      args = ["--log-level", "info",
        "-a", "xrefstyle=full",
        tmp_docs.dir,
        tmp_docs.dir]
      Giblish.application.run args

      # assert that the expected matches the actual
      tmp_docs.check_html_dom adoc_filename do |html_tree|
        ref_nr = 0
        html_tree.css("a").each do |n|
          assert_equal expected_ref_text[ref_nr], n.text
          ref_nr += 1
        end
      end
    end
  end

  def test_xref_and_note_attrib
    # note the 'smart quotes'...
    expected_ref_text = ["Section 2, “My Second Section”",
      "Section 1, “My First Section”"]
    expected_note_text = "TestNote"

    TmpDocDir.open do |tmp_docs|
      # act on the input data
      adoc_filename = tmp_docs.add_doc_from_str @xref_str
      args = ["--log-level", "info",
        "-a", "xrefstyle=full",
        "-a", "note-caption=#{expected_note_text}",
        tmp_docs.dir,
        tmp_docs.dir]
      Giblish.application.run args

      # assert that the expected matches the actual
      tmp_docs.check_html_dom adoc_filename do |html_tree|
        ref_nr = 0
        # assert that the xref==full behaves as expected
        html_tree.css("a").each do |n|
          assert_equal expected_ref_text[ref_nr], n.text
          ref_nr += 1
        end

        html_tree.css(".title").each do |n|
          assert_equal expected_note_text, n.text
        end
      end
    end
  end
end
