#!/usr/bin/env ruby

require "sinatra"
begin
  # used when developping this script
  require_relative "../gh_giblish/lib/giblish/search/request_manager"
rescue LoadError
  # used in deployment
  require "giblish"
end

# Provide the mappings of URI paths that apply to the specific deployment
# setup.
#
# The below example maps the URL www.example.com/ to the local directory
# /var/www/html/mydocs on the web server.
URL_PATH_MAPPINGS = {
  "/" => "/var/www/html/mydocs"
}

# instantiate the one-and-only manager for search requests.
#
# It implements caching of search data internally and this will be
# wasted if a new instance were created for each search request.
request_mgr = Giblish::RequestManager.new(URL_PATH_MAPPINGS)

get "/gibsearch" do
  # This call encapsulates the search and returns an html page
  # with the search result.
  #
  # The search parameters of this request can be fetched from
  # rack's environment.
  request_mgr.response(request.env["rack.request.query_hash"])
end
