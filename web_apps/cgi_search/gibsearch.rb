#!/home/andersr/.rbenv/shims/ruby
## /usr/bin/env ruby
# replace the line above with an absolute path to a ruby interpreter
# if you don't want the system one.

require "cgi"
begin
  # used when developping this script
  require_relative "../gh_giblish/lib/giblish/search/request_manager"
rescue LoadError
  # used in deployment
  require "giblish"
end

# Provide the mappings of URL paths that apply to the specific deployment
# setup.
#
# The below example maps the URI www.exaple.com/ to the local directory
# /home/andersr/repos/gendocs on the web server.
URL_PATH_MAPPINGS = {
  "/" => __dir__.to_s
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
