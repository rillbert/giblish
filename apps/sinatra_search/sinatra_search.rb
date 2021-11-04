#!/usr/bin/env ruby
require "sinatra"
# Toggle the below requires for deployment or development of this script
# respectively
require "giblish"  # used when deploying
# require_relative "../../lib/giblish/search/request_manager"  # used when developping this script


# Provide the mappings of URI paths that apply to the specific deployment 
# setup.
#
# The below example maps the URL www.exaple.com/ to the local directory
# /home/andersr/repos/gendocs on the web server.
URL_PATH_MAPPINGS = {
  "/" => "/home/andersr/repos/gendocs/"
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
