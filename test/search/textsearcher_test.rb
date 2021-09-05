require_relative "../test_helper"
require_relative "../../lib/giblish/search/textsearcher"

module Giblish
  class TestTextSearcher < Minitest::Test
    include Giblish::TestUtils

    TEST_DOC_DIR = "data/testdocs/wellformed/search"

    def setup
      Giblog.setup
    end

    def with_search_testdata
      TmpDocDir.open do |tmpdocdir|
        dstdir = Pathname.new(tmpdocdir.dir) / "dst"
        puts `lib/giblish.rb --log-level info -f html -m #{TEST_DOC_DIR} #{dstdir}`
        assert_equal 0, $?.exitstatus

        dst_tree = PathTree.build_from_fs(dstdir, prune: false)
        yield(dst_tree)
      end
    end

    def test_basic_search_info
      with_search_testdata do |dsttree|
        db = dsttree.node("search_assets/heading_db.json")
        data = JSON.parse(File.read(db.pathname.to_s), symbolize_names: true)

        # two files expected
        assert_equal(2, data[:fileinfos].length)
        expected_title_lines = {"file1.adoc" => 1, "subdir/file2.adoc" => 2}
        data[:fileinfos].each do |info|
          assert(["file1.adoc", "subdir/file2.adoc"].include?(info[:filepath]))
          assert_equal(
            expected_title_lines[info[:filepath]],
            info[:sections][0][:line_no]
          )
        end
      end
    end

    def test_search_parameters
      # use give the bare minima
      uri = "http://www.example.com/my/docs/repo1/sudir1/file_1.html?search-assets-top-rel=../gibsearch_assets&searchphrase=hejsan"
      sp = SearchParameters.new(calling_uri: uri)

      assert_equal("../gibsearch_assets", sp.assets_top_rel.to_s)
      assert_equal("/my/docs/repo1/gibsearch_assets", sp.assets_uri_path.to_s)
      assert_equal("hejsan", sp.searchphrase)
      assert_equal(nil, sp.css_path)
      assert_equal(false, sp.as_regexp?)
      assert_equal(false, sp.consider_case?)

      # use give all values
      uri = "http://www.example.com/my/docs/repo1/sudir1/file_1.html?search-assets-top-rel=../gibsearch_assets&searchphrase=hejsan&css-path=/my/style/sheet.css&consider-case&as-regexp=true"
      sp = SearchParameters.new(calling_uri: uri)

      assert_equal("../gibsearch_assets", sp.assets_top_rel.to_s)
      assert_equal("/my/docs/repo1/gibsearch_assets", sp.assets_uri_path.to_s)
      assert_equal("hejsan", sp.searchphrase)
      assert_equal("/my/style/sheet.css", sp.css_path.to_s)
      assert_equal(true, sp.as_regexp?)
      assert_equal(true, sp.consider_case?)
    end

    def test_search_repo
      # with_search_testdata do |dsttree|

      #   repos = SearchRepoCache.new
      #   ts = TextSearcher.new(repos)

      #   results = ts.search(sp)
      # end
    end
  end
end
