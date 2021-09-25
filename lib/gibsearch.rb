#!/usr/bin/env ruby

require "asciidoctor"
require "cgi"
require_relative "../gh_giblish/lib/giblish/search/request_manager"

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

def hello_world
  require "pp"

  # init a new cgi 'connection'
  cgi = CGI.new
  print cgi.header
  print "<br>"
  print "Useful cgi parameters and variables."
  print "<br>"
  print cgi.public_methods(false).sort
  print "<br>"
  print "<br>"
  print "referer: #{cgi.referer}<br>"
  print "path: #{URI(cgi.referer).path}<br>"
  print "host: #{cgi.host}<br>"
  print "client_sent_topdir: #{cgi["topdir"]}<br>"
  print "<br>"
  print "client_sent_reldir: #{cgi["reltop"]}<br>"
  print "<br>"
  print "ENV: "
  pp ENV
  print "<br>"
end

def search_response(cgi)
  rm = Giblish::CGIRequestManager.new(cgi, {"/" => "/home/andersr/repos/gendocs"})
  rm.response
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
  if ARGV.length == 0
    # 'Normal' cgi usage, as called from a web server

    # init a new cgi 'connection' and print headers
    cgi = CGI.new
    print cgi.header

    begin      
      print search_response(cgi)
    rescue => e
      print e.message
      print ""
      print e.backtrace
      exit 1
    end
    exit 0
  end

  if ARGV.length == 1
    # Run a simple web server to test this locally..
    # and then create the html docs using:
    # giblish -c -m -w <web_root> -r <resource_dir> -s <style_name> -g <git_branch> <src_root> <web_root>
    init_web_server(ARGV[0])
    exit 0
  end
end
