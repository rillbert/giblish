require_relative "../test_helper"
require_relative "../../lib/giblish/search/searchquery"

module Giblish
  class TestSearchQuery < GiblishTestBase
    include Giblish::TestUtils

    TEST_DOC_DIR = "data/testdocs/wellformed/search"

    def test_from_uri
      uris = {
        ok: "http://www.example.com/search?calling-url=http://www.example.com/file_1.html&search-assets-top-rel=../gibsearch_assets&search-phrase=hejsan"
      }

      assert(q = SearchQuery.new(uri: uris[:ok]))
      assert_equal("http://www.example.com/file_1.html", q.calling_url)
      assert_equal(Pathname.new("../gibsearch_assets"), q.search_assets_top_rel)
      assert_equal("hejsan", q.search_phrase)

      uris_missing = {
        missing_1: "http://www.example.com/search?search-assets-top-rel=../gibsearch_assets&search-phrase=hejsan",
        missing_2: "http://www.example.com/search?calling-url=http://www.example.com/file_1.html&search-phrase=hejsan",
        missing_3: "http://www.example.com/search?calling-url=http://www.example.com/file_1.html&search-assets-top-rel=../gibsearch_assets"
      }

      uris_missing.each do |k, v|
        assert_raises(ArgumentError) { SearchQuery.new(uri: v) }
      end

      uri_all_opts = {
        ok: "http://www.example.com/search?calling-url=http://www.example.com/file_1.html" \
        "&search-assets-top-rel=../gibsearch_assets&search-phrase=hejsan" \
        "&css-path=../my/css&consider-case&as-regexp=true"
      }
      q = SearchQuery.new(uri: uri_all_opts[:ok])
      assert_equal(Pathname.new("../my/css"), q.css_path)
      assert_equal(true, q.consider_case?)
      assert_equal(true, q.as_regexp?)

      uri_some_opts = {
        ok: "http://www.example.com/search?calling-url=http://www.example.com/file_1.html" \
        "&search-assets-top-rel=../gibsearch_assets&search-phrase=hejsan" \
        "&as-regexp=true"
      }
      q = SearchQuery.new(uri: uri_some_opts[:ok])
      assert_nil(q.css_path)
      assert_equal(false, q.consider_case?)
      assert_equal(true, q.as_regexp?)
    end

    def test_from_hash
      ok = {
        "calling-url" => "http://www.example.com/file_1.html",
        "search-assets-top-rel" => "../gibsearch_assets",
        "search-phrase" => "hejsan"
      }

      q = SearchQuery.new(query_params: ok)
      assert_equal("http://www.example.com/file_1.html", q.calling_url)
      assert_equal(Pathname.new("../gibsearch_assets"), q.search_assets_top_rel)
      assert_equal("hejsan", q.search_phrase)

      missing = {
        "calling-url" => "http://www.example.com/file_1.html",
        "search-phrase" => "hejsan"
      }
      assert_raises(ArgumentError) { SearchQuery.new(query_params: missing) }
    end
  end
end
