#!/usr/bin/env ruby
require "webrick"

# root = File.expand_path "/tmp/d20210823-302195-1x9pock/dst/"
root = File.expand_path "/home/andersr/repos/gendocs"
server = WEBrick::HTTPServer.new Port: 8000, DocumentRoot: root
trap "INT" do
  server.shutdown
end

server.start
