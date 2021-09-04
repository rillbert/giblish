require_relative "../test_helper"
require_relative "../../lib/giblish/application"

class ResolveDocidTest < Minitest::Test
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

      assert(Giblish.application.run(args))
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

      assert(Giblish.application.run(args))
    end
  end
end
