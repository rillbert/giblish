
require_relative "cmdline"
require_relative "core"
require_relative "utils"

module Giblish
  class Application

    def run_with_args(args)
      run args
    end

    def run_from_cmd_line
      run ARGV
    end

    def run(args)
      # setup logging
      Giblog.setup

      # Parse cmd line
      cmdline = CmdLineParser.new args

      Giblog.logger.debug { "cmd line args: #{cmdline.args.to_s}" }

      # Convert using given args
      begin
        if cmdline.args[:gitRepoRoot]
          Giblog.logger.info {"User asked to parse a git repo"}
          GitRepoParser.new cmdline.args
        else
          tc = TreeConverter.new cmdline.args
#          tc.walk_dirs
          tc.walk_dirs_with_docid
        end
      rescue Exception => e
        puts "Error: #{e.message}"
        puts "\n"
        puts "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
        puts cmdline.usage
      end
    end
  end
end
