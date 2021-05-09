# frozen_string_literal: true

require_relative "cmdline"
require_relative "core"
require_relative "utils"

module Giblish
  # The 'main' class of giblish
  class Application
    # does not return, exits with status code
    def run_from_cmd_line
      status = run(ARGV)
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

      exit_code = execute_conversion(cmdline)
      Giblog.logger.info { "Giblish is done!" } if exit_code.zero?
      exit_code
    end

    private

    # Convert using given args
    # return exit code (0 for success)
    def execute_conversion(cmdline)
      conv_ok = true
      begin
        conv_ok = converter_factory(cmdline).convert
      rescue => e
        log_error e
        conv_ok = false
      end
      conv_ok ? 0 : 1
    end

    # return the converter corresponding to the given cmd line
    # options
    def converter_factory(cmdline)
      if cmdline.args[:gitRepoRoot]
        Giblog.logger.info { "User asked to parse a git repo" }
        GitRepoConverter.new(cmdline.args)
      else
        FileTreeConverter.new(cmdline.args)
      end
    end

    def log_error(exc)
      Giblog.logger.error do
        <<~ERR_MSG
          Error: #{exc.message}
          Backtrace:
          \t#{exc.backtrace.join("\n\t")}

          cmdline.usage
        ERR_MSG
      end
    end
  end
end
