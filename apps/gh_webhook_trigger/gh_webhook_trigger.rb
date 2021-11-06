require "sinatra/base"
require "json"
require "logger"
require_relative "../../lib/giblish/github_trigger/webhook_manager"

# instantiate the one-and-only web-hook-manager
giblish_doc_generator = WebhookManager.new(/svg/, "https://github.com/rillbert/giblish.git", Dir.mktmpdir, "giblish", "docs", dstdir, error_logger)

post "/" do
  gh_data = JSON.parse(request.body.read, symbolized_names: true)
  giblish_doc_generator.run(gh_data)
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
