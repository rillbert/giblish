#!/usr/bin/env ruby

require "asciidoctor"
require "cgi"
require_relative "../gh_giblish/lib/giblish/search/request_manager"

# TODO: Fix dynamic uri-mapping
# This example maps www.mysite.com/ to the local dir /home/andersr/repos/gendocs
URI_MAPPINGS = {"/" => "/home/andersr/repos/gendocs"}

def init_web_server web_root
  require "webrick"

  root = File.expand_path web_root
  puts "Trying to start a WEBrick instance at port 8000 serving files from #{web_root}..."

  server = WEBrick::HTTPServer.new(
    Port: 8000,
    DocumentRoot: root,
    Logger: WEBrick::Log.new("webrick.log", WEBrick::Log::DEBUG)
  )

  puts "WEBrick instance now listening to localhost:8000"

  trap "INT" do
    server.shutdown
  end

  server.start
end

# assemble the html response for a given search request
#
# returns:: 0 for success, 1 for failure
def send_search_response
  cgi = CGI.new
  print cgi.header
  print Giblish::CGIRequestManager.new(cgi, URI_MAPPINGS).response
  0
rescue => e
  print e.message
  print "<br>"
  print e.backtrace
  1
end

# Usage:
#   to start a local web server for development work
# ruby gibsearch.cgi <web_root>
#
#   to run as a cgi script via a previously setup web server
# gibsearch.cgi
#
if __FILE__ == $PROGRAM_NAME

  STDOUT.sync = true

  # called without arguments (typically via a web server)
  if ARGV.length == 0
    exit(send_search_response)
  end

  # Starts up a simple web server to test this locally.
  #
  # A typical dev flow can look as:
  #
  # 1. Create your html docs using eg
  # giblish -m -r <resource_dir> -s <style_name> <src_root> <dst_root>
  # 2. Copy or symlink this script into <dst_root> as 'gibsearch.cgi'
  # 3. Start a simple web server to test this as
  # .../gibsearch.rb <dst_root>
  if ARGV.length == 1
    init_web_server(ARGV[0])
    exit 0
  end
end
