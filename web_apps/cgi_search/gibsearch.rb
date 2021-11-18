#!/usr/bin/env ruby

require "cgi"
# Toggle the below requires for deployment or development of this script
# respectively
require "giblish" # used when deploying
# require_relative "../gh_giblish/lib/giblish/search/request_manager"  # used when developping this script

# Provide the mappings of URL paths that apply to the specific deployment
# setup.
#
# The below example maps the URI www.exaple.com/ to the local directory
# /home/andersr/repos/gendocs on the web server.
URL_PATH_MAPPINGS = {
  "/" => "/home/andersr/repos/gendocs/"
}

# This is run for each CGI request.
#
# Exits with 0 for success, 1 for failure
if __FILE__ == $PROGRAM_NAME
  $stdout.sync = true

  begin
    cgi = CGI.new

    # assemble the html response for a given search request
    print cgi.header
    print Giblish::RequestManager.new(URL_PATH_MAPPINGS).response(cgi)
    0
  rescue => e
    print e.message
    print "<br>"
    print e.backtrace
    1
  end
end
