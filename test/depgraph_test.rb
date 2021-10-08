# frozen_string_literal: true

require "fileutils"
require "test_helper"
require_relative "../lib/giblish/utils"

class DepGraphTests < Minitest::Test
  include Giblish::TestUtils

  def setup
    # setup logging
    Giblog.setup
  end

  def test_graph_is_created_depending_on_graphviz
    TmpDocDir.open(test_data_subdir: "src_top") do |tmp_docs|
      dst_top = "#{tmp_docs.dir}/dst_top"

      args = ["--log-level", "info",
        "--resolve-docid",
        tmp_docs.src_data_top.join("wellformed/docidtest"),
        dst_top]
      Giblish.application.run args

      if Giblish.which("dot")
        assert(File.exist?("#{dst_top}/gibgraph.html"))
      else
        assert(!File.exist?("#{dst_top}/gibgraph.html"))
      end

      assert(File.exist?("#{dst_top}/index.html"))
      assert(!File.exist?("#{dst_top}/gibgraph.svg"))
    end
  end
end
