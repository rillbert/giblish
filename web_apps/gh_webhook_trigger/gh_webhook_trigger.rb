# This app will trigger a document generation from a 'push' github webhook
require "sinatra"
require "json"
require "pathname"
require "logger"

begin
  # used during development/testing
  require_relative "../../lib/giblish/github_trigger/webhook_manager"
rescue LoadError
  # used in production
  require "giblish"
end

# setup a specific logger for requests
accesslog_path = Pathname.new(__dir__).join("log/access.log")
accesslog_path.dirname.mkpath
access_logger = ::Logger.new(accesslog_path.to_s)

# the target directory on the server's file system
DSTDIR = "/var/www/rillbert_se/html/public/giblish_examples/giblish"
clone_dir = Dir.mktmpdir

# setup the doc generation once-and-for-all
doc_generator = Giblish::GenerateFromRefs.new(
  "https://github.com/rillbert/giblish.git",
  /main/,
  clone_dir,
  "giblish",
  %W[-l debug -j data/],
  ".",
  DSTDIR,
  access_logger
)

post "/" do
  gh_data = JSON.parse(request.body.read, symbolize_names: true)
  # access_logger.debug { "Calling webhook manager with data: #{gh_data}" }
  doc_generator.docs_from_gh_webhook(gh_data)
end

get "/" do
  ""
end
