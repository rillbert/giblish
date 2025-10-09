require_relative "../test_helper"
require_relative "../../lib/giblish/search/textsearcher"

module Giblish
  class TestTextSearcher < GiblishTestBase
    include Giblish::TestUtils

    TEST_DOC_DIR = "data/testdocs/wellformed/search"

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
        assert_equal 0, $?.exitstatus

        dst_tree = Gran::PathTree.build_from_fs(dstdir, prune: false)
        yield(dst_tree)
      end
    end

    def test_basic_search_info
      with_search_testdata do |dsttree|
        db = dsttree.node("gibsearch_assets/heading_db.json")
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

    def test_uri_mapping
      uri = "http://www.example.com/search_actionf?calling-url=http://www.example.com/my/docs/repo1/subdir1/file_1.html&search-assets-top-rel=../gibsearch_assets&search-phrase=hejsan"

      # use one mapping
      mapping = {"/my/docs" => Pathname.new(__FILE__).dirname}
      sp = SearchParameters.from_uri(uri, uri_mappings: mapping)
      assert_equal(
        Pathname.new("#{__dir__}/repo1/subdir1"),
        sp.send(:uri_to_fs, "/my/docs/repo1/subdir1")
      )

      # use two mappings
      mapping = {
        "/my/docs" => Pathname.new(__FILE__).dirname,
        "/my/docs/repo1/" => Pathname.new("/")
      }
      sp = SearchParameters.from_uri(uri, uri_mappings: mapping)
      assert_equal(
        Pathname.new("#{__dir__}/newdir"),
        sp.send(:uri_to_fs, "/my/docs/newdir")
      )
      assert_equal(
        Pathname.new("/subdir1"),
        sp.send(:uri_to_fs, "/my/docs/repo1/subdir1")
      )
      assert_equal(
        Pathname.new("/no/matching/mapping"),
        sp.send(:uri_to_fs, "/no/matching/mapping")
      )
    end

    def test_search_parameters
      # use an ok prefix
      mapping = {"/my/docs" => Pathname.new(__FILE__).dirname}

      # user give the bare minima
      uri = "http://www.example.com/search_actionf?calling-url=http://www.example.com/my/docs/repo1/subdir1/file_1.html&search-assets-top-rel=../gibsearch_assets&search-phrase=hejsan"
      sp = SearchParameters.from_uri(uri, uri_mappings: mapping)

      assert_equal("/my/docs/repo1/gibsearch_assets", sp.assets_uri_path.to_s)
      assert_equal("/my/docs/repo1", sp.uri_path_repo_top.to_s)
      assert_equal("#{__dir__}/repo1/gibsearch_assets", sp.assets_fs_path.to_s)
      assert_equal("../gibsearch_assets", sp.search_assets_top_rel.to_s)
      assert_equal("subdir1/file_1.html", sp.repo_file_path.to_s)
      assert_equal("hejsan", sp.search_phrase)
      assert_nil(sp.css_path)
      assert_equal(false, sp.as_regexp?)
      assert_equal(false, sp.consider_case?)

      # user give all values
      uri = "http://www.example.com/search_actionf?calling-url=http://www.example.com/my/docs/repo1/subdir1/file_1.html&search-assets-top-rel=../gibsearch_assets&search-phrase=hejsan&css-path=/my/style/sheet.css&consider-case&as-regexp=true"
      sp = SearchParameters.from_uri(uri, uri_mappings: mapping)

      assert_equal("/my/docs/repo1/gibsearch_assets", sp.assets_uri_path.to_s)
      assert_equal("/my/docs/repo1", sp.uri_path_repo_top.to_s)
      assert_equal("#{__dir__}/repo1/gibsearch_assets", sp.assets_fs_path.to_s)
      assert_equal("../gibsearch_assets", sp.search_assets_top_rel.to_s)
      assert_equal("subdir1/file_1.html", sp.repo_file_path.to_s)
      assert_equal("hejsan", sp.search_phrase)
      assert_equal("/my/style/sheet.css", sp.css_path.to_s)
      assert_equal(true, sp.as_regexp?)
      assert_equal(true, sp.consider_case?)
    end

    def test_url_builder
      # use an ok prefix
      mapping = {"/my/docs" => Pathname.new(__FILE__).dirname}

      # user give the bare minima
      uri = "http://www.example.com:8000/search_actionf?calling-url=http://www.example.com:8000/my/docs/repo1/subdir1/file_1.html&search-assets-top-rel=../gibsearch_assets&search-phrase=hejsan"
      sp = SearchParameters.from_uri(uri, uri_mappings: mapping)

      assert_equal(
        "http://www.example.com:8000/my/docs/repo1/file1.html#_my_id",
        sp.url("file1.adoc", "_my_id").to_s
      )
    end

    # script under url: <url>/scripts/gibsearch
    # __FILE__ in script /var/www/myscripts/gibsearch.rb
    #
    # search_asset_top on file system: /var/www/my/docs/repo1/gibsearch_assets
    # we need the prefix of the file system path, in this case '/var/www/'
    def test_search_data_repo
      with_search_testdata do |dsttree|
        # fake minimal search request from file1 deployed to /my/docs/repo1
        uri = "http://www.example.com/search?calling-url=http://www.example.com/file_1.html&search-assets-top-rel=./gibsearch_assets&search-phrase=hejsan"
        sp = SearchParameters.from_uri(uri, uri_mappings: {"/" => dsttree.pathname})
        repo = SearchDataRepo.new(sp.assets_fs_path)

        sec = repo.in_section("file1.adoc", 1)
        assert_equal("File 1", sec[:title])

        sec = repo.in_section("file1.adoc", 2)
        assert_equal("File 1", sec[:title])

        sec = repo.in_section("file1.adoc", 6)
        assert_equal("Paragraph 1", sec[:title])

        sec = repo.in_section("file1.adoc", 75)
        assert_equal("Sub section 2", sec[:title])
      end
    end

    def test_text_searcher
      # raise NotImplementedError
      with_search_testdata do |dsttree|
        searcher = TextSearcher.new(SearchRepoCache.new)

        # fake minimal search request from file1 deployed to /my/docs/repo1
        uri = "http://www.example.com/search?calling-url=http://www.example.com/file_1.html&search-assets-top-rel=./gibsearch_assets&search-phrase=text"
        sp = SearchParameters.from_uri(uri, uri_mappings: {"/" => dsttree.pathname})

        results = searcher.search(sp)
        expected_keys = [Pathname.new("file1.adoc"), Pathname.new("subdir/file2.adoc")]

        # at least check that the number of matches is consistent with
        # the content of the test docs
        assert_equal(expected_keys, results.keys)
        assert_equal(4, results[expected_keys[0]][:sections].count)
        assert_equal(2, results[expected_keys[1]][:sections].count)
      end
    end

    def test_text_search_consider_case
      with_search_testdata do |dsttree|
        searcher = TextSearcher.new(SearchRepoCache.new)

        # fake minimal search request from file1 deployed to /my/docs/repo1
        uri = "http://www.example.com/search?calling-url=http://www.example.com/file_1.html&search-assets-top-rel=./gibsearch_assets&search-phrase=More&consider-case"
        sp = SearchParameters.from_uri(uri, uri_mappings: {"/" => dsttree.pathname})

        results = searcher.search(sp)
        expected_keys = [Pathname.new("file1.adoc"), Pathname.new("subdir/file2.adoc")]

        # at least check that the number of matches is consistent with
        # the content of the test docs
        assert_equal(expected_keys, results.keys)
        assert_equal(2, results[expected_keys[0]][:sections].count)
        assert_equal(1, results[expected_keys[1]][:sections].count)
      end
    end

    def test_text_search_use_regexp
      with_search_testdata do |dsttree|
        searcher = TextSearcher.new(SearchRepoCache.new)

        # fake minimal search request from file1 deployed to /my/docs/repo1
        uri = "http://www.example.com/search?calling-url=http://www.example.com/file_1.html&search-assets-top-rel=./gibsearch_assets&search-phrase=Some.%2Athat&as-regexp"
        sp = SearchParameters.from_uri(uri, uri_mappings: {"/" => dsttree.pathname})

        results = searcher.search(sp)
        expected_keys = [Pathname.new("file1.adoc"), Pathname.new("subdir/file2.adoc")]

        # at least check that the number of matches is consistent with
        # the content of the test docs
        assert_equal(expected_keys, results.keys)
        assert_equal(1, results[expected_keys[0]][:sections].count)
        assert_equal(1, results[expected_keys[1]][:sections].count)
      end
    end

    def test_repo_caching
      TmpDocDir.open do |tmpdocdir|
        dstdir = Pathname.new(tmpdocdir.dir) / "dst"
        `lib/giblish.rb --log-level info -f html -m #{TEST_DOC_DIR} #{dstdir}`
        assert_equal 0, $?.exitstatus

        dst_tree = Gran::PathTree.build_from_fs(dstdir, prune: false)

        rc = SearchRepoCache.new
        searcher = TextSearcher.new(rc)

        # fake minimal search request from file1 deployed to /my/docs/repo1
        uri = "http://www.example.com/search?calling-url=http://www.example.com/file_1.html&search-assets-top-rel=./gibsearch_assets&search-phrase=text"
        sp = SearchParameters.from_uri(uri, uri_mappings: {"/" => dst_tree.pathname})

        # check that two consecutive searches returns the same repo
        searcher.search(sp)
        id1 = rc.repo(sp).object_id
        searcher.search(sp)
        assert_equal(id1, rc.repo(sp).object_id)

        # sleep as long as the mtime granularity and then recreate all
        # search data files
        sleep(1)
        `lib/giblish.rb --log-level info -f html -m #{TEST_DOC_DIR} #{dstdir}`
        assert_equal 0, $?.exitstatus

        # check that the repo is now different from above since
        # it has been reread from the file system
        searcher.search(sp)
        assert(id1 != rc.repo(sp).object_id)
      end
    end
  end
end
