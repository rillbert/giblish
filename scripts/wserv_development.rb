#!/usr/bin/env ruby
#
# Starts up a simple web server for local testing of generated documents.
#
# A typical dev flow:
#
# 1. Create your html docs using giblish
# 2. If you want to enable text search, copy or symlink the `gibsearch.rb` script 
# from the giblish gem to the correct location under the target tree.
# 3. Run this script to kick-off a web server that serves your html docs.

require "webrick"

# the root directory for the web server
web_root = "/home/andersr/development/generated_docs"
# the port the web server listens to
port = 8000


puts "Trying to start a WEBrick instance at port #{port} serving files from #{web_root}..."
server = WEBrick::HTTPServer.new(
  Port: port,
  DocumentRoot: File.expand_path(web_root),
  Logger: WEBrick::Log.new("webrick.log", WEBrick::Log::DEBUG)
)

puts "WEBrick instance now listening to localhost:#{port}"
trap "INT" do
  server.shutdown
end

server.start
