require 'sinatra'
require 'json'

post '/docgen' do
  push = JSON.parse(request.body.read, symbolized_names: true)
  puts "JSON from github: #{push.inspect}"
end
