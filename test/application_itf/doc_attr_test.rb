# frozen_string_literal: true

require "oga"
require_relative "../test_helper"

module Giblish
  # tests that asciidoctor document attributes can be set via the -a or
  # --attributes flag at invocation.
  class DocAttrTest < Minitest::Test
    include Giblish::TestUtils

    IDPREFIX_DEFAULT = <<~ID_SOURCE
      = Test idprefix settings

      == Paragraph 1

      Some random text

      [[my_id]]
      == Paragraph 2

      More random text
    ID_SOURCE

    IDPREFIX_WITH_CUSTOM = <<~ID_SOURCE
      = Test idprefix settings
      :idprefix: custom

      == Paragraph 1

      Some random text

      [[my_p2_id]]
      == Paragraph 2

      More random text
    ID_SOURCE

    # use a template xref doc
    XREF_DOC_STR = <<~XREF_TEST
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

    def convert(src_tree, configurator)
      data_provider = DataDelegator.new(SrcFromFile.new, configurator.doc_attr)
      src_tree.traverse_preorder do |level, node|
        next unless node.leaf?

        node.data = data_provider
      end

      TreeConverter.new(src_tree, configurator.config_opts.dstdir, configurator.build_options).run
    end

    def test_xref_short_style_via_attrib_flag
      TmpDocDir.open(preserve: false) do |tmp_docs|
        tmp_docs.add_doc_from_str(XREF_DOC_STR)

        args = ["--log-level", "info",
          "-a", "xrefstyle=short",
          tmp_docs.dir,
          tmp_docs.dir]
        convert(
          PathTree.build_from_fs(tmp_docs.dir),
          Configurator.new(CmdLine.new.parse(args))
        )

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
        tmp_docs.add_doc_from_str(XREF_DOC_STR)

        args = ["--log-level", "info",
          "-a", "xrefstyle=full",
          tmp_docs.dir,
          tmp_docs.dir]
        convert(
          PathTree.build_from_fs(tmp_docs.dir),
          Configurator.new(CmdLine.new.parse(args))
        )

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
        tmp_docs.add_doc_from_str(XREF_DOC_STR)

        expected_note_text = "TestNote"

        args = ["--log-level", "info",
          "-a", "xrefstyle=full",
          "-a", "note-caption=#{expected_note_text}",
          tmp_docs.dir,
          tmp_docs.dir]
        convert(
          PathTree.build_from_fs(tmp_docs.dir),
          Configurator.new(CmdLine.new.parse(args))
        )

        result = PathTree.build_from_fs(tmp_docs.dir) { |p| p.extname == ".html" && p.basename.to_s != "index.html" }
        assert_equal(1, result.leave_pathnames.count)

        # note the 'smart quotes'...
        expected_ref_text = ["Section 2, “My Second Section”", "Section 1, “My First Section”"]

        doc_count = 0
        tmp_docs.get_html_dom(result) do |node, dom|
          next if /index.html$/.match?(node.pathname.to_s)

          doc_count += 1
          ref_nr = 0
          dom.xpath("//a").each do |el|
            assert_equal(expected_ref_text[ref_nr], el.text)
            ref_nr += 1
          end
          assert(ref_nr > 0)

          dom.css(".title").each do |n|
            assert_equal expected_note_text, n.text
          end
        end
        assert_equal(1, doc_count)
      end
    end

    def test_custom_idprefix
      TmpDocDir.open(preserve: false) do |tmp_docs|
        topdir = Pathname.new(tmp_docs.dir)
        src_topdir = topdir / "src"

        # create adocs from the test strings
        file1 = tmp_docs.add_doc_from_str(IDPREFIX_DEFAULT, src_topdir)
        file2 = tmp_docs.add_doc_from_str(IDPREFIX_WITH_CUSTOM, src_topdir)
        # p_top = Pathname.new(tmp_docs.dir) / src_topdir

        src_tree = PathTree.build_from_fs(tmp_docs.dir)
        convert(
          src_tree,
          Configurator.new(CmdLine.new.parse(%W[-f html #{topdir} #{topdir / "dst"}]))
        )

        # check that the idprefix is as expected
        expected_ids = {
          Pathname.new(file1).basename.sub_ext(".html") => ["_paragraph_1", "my_id"],
          Pathname.new(file2).basename.sub_ext(".html") => ["customparagraph_1", "my_p2_id"]
        }
        html_result = PathTree.build_from_fs(topdir / "dst", prune: false) { |p| p.extname == ".html" }
        count = 0
        tmp_docs.get_html_dom(html_result) do |node, document|
          p = node.pathname
          next unless expected_ids.key?(p.basename)

          count += 1
          # select all 'id' attributes and check that they start with
          # the right prefix
          i = 0
          document.xpath("//h2[@id]").each do |el|
            assert_equal(expected_ids[p.basename][i], el["id"])
            i += 1
          end
          assert(1 > 0)
        end
        assert_equal(expected_ids.keys.count, count)

        # now re-do the html generation using a hard-coded idprefix
        convert(
          src_tree,
          Configurator.new(CmdLine.new.parse(%W[-f html -a idprefix=idefix #{topdir} #{topdir / "dst"}]))
        )

        expected_ids = {
          Pathname.new(file1).basename.sub_ext(".html") => ["idefixparagraph_1", "my_id"],
          Pathname.new(file2).basename.sub_ext(".html") => ["idefixparagraph_1", "my_p2_id"]
        }
        count = 0
        tmp_docs.get_html_dom(html_result) do |node, document|
          p = node.pathname
          next unless expected_ids.key?(p.basename)

          count += 1
          # select all 'id' attributes and check that they start with
          # the right prefix
          i = 0
          document.xpath("//h2[@id]").each do |el|
            assert_equal(expected_ids[p.basename][i], el["id"])
            i += 1
          end
          assert(1 > 0)
        end
        assert_equal(expected_ids.keys.count, count)
      end
    end
  end
end
