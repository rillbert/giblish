require 'oga'
require "test_helper"
require_relative "../lib/giblish/utils.rb"
require_relative "../lib/giblish/docid.rb"

# tests that asciidoc attributes can be set via the -a or
# --attributes flag at invocation.
class AttributesTest < Minitest::Test

  include Giblish::TestUtils

  def setup

    # create dir for test docs
    @src_root = "#{File.expand_path(File.dirname(__FILE__))}/../data/testdocs/runtime"
    FileUtils.mkdir_p @src_root

    setup_log_and_paths
  end

  def teardown
    dry_run = false
    teardown_log_and_paths dry_run: dry_run
    FileUtils.rm_r @src_root unless dry_run
  end

  def test_xref_short_style_via_attrib_flag

    xref_doc = <<~EOF
      = Test xref handling
      :numbered:
      
      == My First Section
      
      This is a ref to <<section_id_2>> via explicit id (it is not possible to use automatic id 
      when an explicit id is set).

      [[section_id_2]]      
      == My Second Section
      
      This is a reference to <<_my_first_section>> via automatic id.
    EOF
    expected_ref_text = ["Section 2",
                         "Section 1"]

    # write doc to file
    file = File.open(@src_root + "/tst_xref_styles.adoc", "w")
    file.puts xref_doc
    file.close

    # run giblish on the doc
    args = ["--log-level", "info",
            "-a", "xrefstyle=short",
            @src_root,
            @dst_root]
    Giblish.application.run_with_args args

    # parse the generated html
    outfile = "#{@dst_root}/tst_xref_styles.html"
    handle = File.open(outfile)
    document = Oga.parse_html(handle)

    # assert that the expected matches the actual
    ref_nr = 0
    document.css('a').each do |n|
      assert_equal expected_ref_text[ref_nr], n.text
      ref_nr+=1
    end
  end

  def test_xref_full_style_via_attrib_flag

    xref_doc = <<~EOF
      = Test xref handling
      :numbered:
      
      == My First Section
      
      This is a ref to <<section_id_2>> via explicit id (it is not possible to use automatic id 
      when an explicit id is set).

      [[section_id_2]]      
      == My Second Section
      
      This is a reference to <<_my_first_section>> via automatic id.
    EOF

    # note the 'smart quotes'...
    expected_ref_text = ['Section 2, “My Second Section”',
                         'Section 1, “My First Section”']

    # write doc to file
    file = File.open(@src_root + "/tst_xref_styles.adoc", "w")
    file.puts xref_doc
    file.close

    # run giblish on the doc
    args = ["--log-level", "info",
            "-a", "xrefstyle=full",
            @src_root,
            @dst_root]
    Giblish.application.run_with_args args

    # parse the generated html
    outfile = "#{@dst_root}/tst_xref_styles.html"
    handle = File.open(outfile)
    document = Oga.parse_html(handle)

    # assert that the expected matches the actual
    ref_nr = 0
    document.css('a').each do |n|
      assert_equal expected_ref_text[ref_nr], n.text
      ref_nr+=1
    end
  end
end
