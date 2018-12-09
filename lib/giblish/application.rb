
require_relative "cmdline"
require_relative "core"
require_relative "utils"

module Giblish
  class Application

    # return exit status (0 for success)
    def run_with_args(args)
      run args
    end

    # does not return, exits with status code
    def run_from_cmd_line
      status = run ARGV
      exit(status)
    end

    # return exit status (0 for success)
    def run(args)
      # force immediate output
      $stdout.sync = true

      # setup logging
      Giblog.setup

      # Parse cmd line
      cmdline = CmdLineParser.new args

      Giblog.logger.debug { "cmd line args: #{cmdline.args}" }

      # Convert using given args
      begin
        if cmdline.args[:gitRepoRoot]
          Giblog.logger.info { "User asked to parse a git repo" }
          gc = GitRepoConverter.new cmdline.args
          gc.convert
        else
          tc = FileTreeConverter.new cmdline.args
          tc.convert
        end
        Giblog.logger.info { "Giblish is done!" }
        0
      rescue Exception => e
        log_error e
        1
      end
    end

    private

    def log_error(ex)
      Giblog.logger.error do
        <<~ERR_MSG
          Error: #{ex.message}
          Backtrace:
          \t#{ex.backtrace.join("\n\t")}

          cmdline.usage
        ERR_MSG
      end
    end
  end
end
