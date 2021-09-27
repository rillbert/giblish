require_relative "../test_helper"
require_relative "../../lib/giblish/search/request_manager"

module Giblish
  class CGIRequestManagerTest < Minitest::Test
    include Giblish::TestUtils

    TEST_DOC_DIR = "data/testdocs/wellformed/search"

    def setup
      Giblog.setup
    end

    # The test data is stored as
    # |- dst
    #     |- gibsearch_assets
    #         |- file1.adoc
    #         |- subdir
    #              |- file2.adoc
    def with_search_testdata
      TmpDocDir.open do |tmpdocdir|
        dstdir = Pathname.new(tmpdocdir.dir) / "dst"
        `lib/giblish.rb --log-level info -f html -m #{TEST_DOC_DIR} #{dstdir}`
        assert_equal(0, $?.exitstatus)

        dst_tree = PathTree.build_from_fs(dstdir, prune: false)
        yield(dst_tree)
      end
    end

    def test_basic_search_info
      fake_cgi = {
        "calling-url" => "http://www.example.com/file1.html",
        "search-assets-top-rel" => "./gibsearch_assets",
        "search-phrase" => "text"
      }
      with_search_testdata do |dsttree|
        rm = CGIRequestManager.new(fake_cgi, {"/" => dsttree.pathname.to_s})
        File.write("s_result.html", rm.response)
      end
    end
  end
end
