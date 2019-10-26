require "test_helper"
require_relative "../lib/giblish/utils.rb"
require_relative "../lib/giblish/docid.rb"

class DocidCollectorTest < Minitest::Test
  include Giblish::TestUtils

  def setup
    # setup logging
    Giblog.setup
  end

  def test_basic_docid_resolution_html
    TmpDocDir.open() do |tmp_docs|
      src_top = tmp_docs.dir + "/src_top"
      dst_top = tmp_docs.dir + "/dst_top"
      copy_test_docs_to_dir src_top

      # act on the input data
      args = ["--log-level", "warn",
              "-d",
              Pathname.new(src_top).join("wellformed/docidtest").to_s,
              dst_top.to_s]
      status = Giblish.application.run_with_args args

      # assert expected
      assert_equal 0,status
    end
  end

  def test_basic_docid_resolution_pdf
    TmpDocDir.open() do |tmp_docs|
      src_top = tmp_docs.dir + "/src_top"
      dst_top = tmp_docs.dir + "/dst_top"
      copy_test_docs_to_dir src_top

      args = ["--log-level", "warn",
              "-d",
              "-f", "pdf",
              Pathname.new(src_top).join("wellformed/docidtest").to_s,
              dst_top]

      status = Giblish.application.run_with_args args
      assert_equal 0,status
    end

  end
end
