require "minitest"
require "minitest/autorun"
require "rack/test"
require "sinatra/base"
require_relative "../sinatra_search/sinatra_search"

class SearchAppTest < MiniTest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def test_search_missing_parameters
    response = get("/gibsearch")
    assert(response.errors)
    assert(response.errors.lines[0].include?("ArgumentError"))
    assert_equal(500,response.status)
  end

  def test_ok_search    
    response = get("/gibsearch?search-phrase=vironova&calling-url=http%3A%2F%2Flocalhost%3A8000%2Fdocs%2Fblah%2Fmain%2Findex.html&search-assets-top-rel=gibsearch_assets&css-path=")
    assert_equal(200,response.status)
  end
end
