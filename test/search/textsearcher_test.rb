require_relative "../test_helper"
require_relative "../../lib/giblish/search/textsearcher"

module Giblish
  class TestTextSearcher < Minitest::Test
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
        puts `lib/giblish.rb --log-level info -f html -m #{TEST_DOC_DIR} #{dstdir}`
        assert_equal 0, $?.exitstatus

        dst_tree = PathTree.build_from_fs(dstdir, prune: false)
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
      uri = "http://www.example.com/my/docs/repo1/subdir1/file_1.html?search-assets-top-rel=../gibsearch_assets&searchphrase=hejsan"

      # use one mapping
      mapping = {"/my/docs" => Pathname.new(__FILE__).dirname}
      sp = SearchParameters.new(calling_uri: uri, uri_mappings: mapping)
      assert_equal(
        Pathname.new("#{__dir__}/repo1/subdir1"),
        sp.send(:uri_to_fs, "/my/docs/repo1/subdir1")
      )

      # use two mappings
      mapping = {
        "/my/docs" => Pathname.new(__FILE__).dirname,
        "/my/docs/repo1/" => Pathname.new("/")
      }
      sp = SearchParameters.new(calling_uri: uri, uri_mappings: mapping)
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

      # use give the bare minima
      uri = "http://www.example.com/my/docs/repo1/subdir1/file_1.html?search-assets-top-rel=../gibsearch_assets&searchphrase=hejsan"
      sp = SearchParameters.new(calling_uri: uri, uri_mappings: mapping)

      assert_equal("/my/docs/repo1/gibsearch_assets", sp.assets_uri_path.to_s)
      assert_equal("/my/docs/repo1", sp.uri_path_repo_top.to_s)
      assert_equal("#{__dir__}/repo1/gibsearch_assets", sp.assets_fs_path.to_s)
      assert_equal("../gibsearch_assets", sp.assets_top_rel.to_s)
      assert_equal("subdir1/file_1.html", sp.repo_file_path.to_s)
      assert_equal("hejsan", sp.searchphrase)
      assert_equal(nil, sp.css_path)
      assert_equal(false, sp.as_regexp?)
      assert_equal(false, sp.consider_case?)

      # use give all values
      uri = "http://www.example.com/my/docs/repo1/subdir1/file_1.html?search-assets-top-rel=../gibsearch_assets&searchphrase=hejsan&css-path=/my/style/sheet.css&consider-case&as-regexp=true"
      sp = SearchParameters.new(calling_uri: uri, uri_mappings: mapping)

      assert_equal("/my/docs/repo1/gibsearch_assets", sp.assets_uri_path.to_s)
      assert_equal("/my/docs/repo1", sp.uri_path_repo_top.to_s)
      assert_equal("#{__dir__}/repo1/gibsearch_assets", sp.assets_fs_path.to_s)
      assert_equal("../gibsearch_assets", sp.assets_top_rel.to_s)
      assert_equal("subdir1/file_1.html", sp.repo_file_path.to_s)
      assert_equal("hejsan", sp.searchphrase)
      assert_equal("/my/style/sheet.css", sp.css_path.to_s)
      assert_equal(true, sp.as_regexp?)
      assert_equal(true, sp.consider_case?)
    end

    # script under url: <url>/scripts/gibsearch
    # __FILE__ in script /var/www/myscripts/gibsearch.rb
    #
    # search_asset_top on file system: /var/www/my/docs/repo1/gibsearch_assets
    # we need the prefix of the file system path, in this case '/var/www/'
    def test_search_data_repo
      with_search_testdata do |dsttree|
        # fake minimal search request from file1 deployed to /my/docs/repo1
        uri = "http://www.example.com/file_1.html?search-assets-top-rel=./gibsearch_assets&searchphrase=hejsan"
        sp = SearchParameters.new(
          calling_uri: uri,
          uri_mappings: {"/" => dsttree.pathname}
        )
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

    def test_search_repo
      # raise NotImplementedError
      with_search_testdata do |dsttree|
        searcher = TextSearcher.new(SearchRepoCache.new)

        # fake minimal search request from file1 deployed to /my/docs/repo1
        uri = "http://www.example.com/file_1.html?search-assets-top-rel=./gibsearch_assets&searchphrase=hejsan"
        sp = SearchParameters.new(
          calling_uri: uri,
          uri_mappings: {"/" => dsttree.pathname}
        )

        results = searcher.search(sp)
        p results
      end
    end
  end
end
