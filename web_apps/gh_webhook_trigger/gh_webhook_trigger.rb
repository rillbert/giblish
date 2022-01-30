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

# instantiate the one-and-only web-hook-manager
DSTDIR = "/var/www/rillbert_se/html/public/giblish_examples/giblish"
clone_dir = Dir.mktmpdir

# setup the doc generation once-and-for-all
doc_generator = Giblish::GenerateFromRefs.new(
  "https://github.com/rillbert/giblish.git", 
  /svg/, 
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

# class GenerateDocsFromGitHubHook < Sinatra::Base
#   ::Logger.class_eval { alias_method :write, :<< }

#   accesslog_path = Pathname.new(__dir__).join("../log/access.log")
#   accesslog_path.dirname.mkpath
#   access_logger = ::Logger.new(accesslog_path.to_s)

#   errorlog_path = Pathname.new(__dir__).join("log/error.log")
#   errorlog_path.dirname.mkpath
#   error_logger = ::File.new(errorlog_path.to_s, "a+")
#   error_logger.sync = true

#   configure do
#     use ::Rack::CommonLogger, access_logger
#   end

#   before {
#     env["rack.errors"] = error_logger
#   }

#   # instantiate the one-and-only web-hook-manager
#   wm = WebhookManager.new(/svg/, "https://github.com/rillbert/giblish.git", Dir.mktmpdir, "giblish", "docs", dstdir, error_logger)

#   post "/payload" do
#     gh_data = JSON.parse(request.body.read, symbolized_names: true)
#     wm.run(gh_data)
#   end
# end
