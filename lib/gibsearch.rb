#!/usr/bin/env ruby

require "cgi"
require "giblish"

# Configure the mappings from uri paths to the local paths on your server.
#
# The mappings are used by the CGIRequestManager to include correct url:s for the 
# clickable links sent back to the user.
# 
# The example maps the URI www.example.com/my/docroot to the local dir /usr/local/docsite
# on the server.
URI_MAPPINGS = {
  "/my/docroot_1" => "/usr/local/docsite",
  "/my/other/docroot" => "/var/www/html"
}

# This is run for each CGI request.
#
# Exits with 0 for success, 1 for failure
if __FILE__ == $PROGRAM_NAME
  STDOUT.sync = true

  begin
    cgi = CGI.new

    # assemble the html response for a given search request
    print cgi.header
    print Giblish::CGIRequestManager.new(cgi, URI_MAPPINGS).response
    0
  rescue => e
    print e.message
    print "<br>"
    print e.backtrace
    1
  end
end
