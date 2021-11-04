#!/usr/bin/env ruby
require "sinatra"
require "giblish"
# Uncomment this when doing development on this code.
# require_relative "../../lib/giblish/search/request_manager"

# Provide the mappings that apply to the specific deployment 
# setup
URL_PATH_MAPPINGS = {
  "/" => "/home/andersr/repos/gendocs/"
}

# instantiate the one-and-only manager for search requests.
#
# It implements caching of search data internally and this will be
# wasted if a new instance were created for each search request.
request_mgr = Giblish::RequestManager.new(URL_PATH_MAPPINGS)

get "/gibsearch" do
  request_mgr.response(request.env["rack.request.query_hash"])
end
