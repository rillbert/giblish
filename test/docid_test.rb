require "test_helper"
require_relative "../lib/giblish/utils"
require_relative "../lib/giblish/docid"

class DocidCollectorTest < Minitest::Test
  include Giblish::TestUtils

  def setup
    # setup logging
    Giblog.setup
  end

  def test_basic_docid_resolution_html
    TmpDocDir.open(test_data_subdir: "src_top") do |tmp_docs|
      dst_top = tmp_docs.dir + "/dst_top"

      # act on the input data
      args = ["--log-level", "warn",
        "-d",
        tmp_docs.src_data_top.join("wellformed/docidtest"),
        dst_top.to_s]
      status = Giblish.application.run args

      # assert expected
      assert_equal 0, status
    end
  end

  def test_basic_docid_resolution_pdf
    TmpDocDir.open(test_data_subdir: "src_top") do |tmp_docs|
      dst_top = tmp_docs.dir + "/dst_top"

      args = ["--log-level", "warn",
        "-d",
        "-f", "pdf",
        tmp_docs.src_data_top.join("wellformed/docidtest"),
        dst_top]

      status = Giblish.application.run args
      assert_equal 0, status
    end
  end
end
