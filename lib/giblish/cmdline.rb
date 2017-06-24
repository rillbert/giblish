#!/usr/bin/ruby

require_relative "utils"
require_relative "version"

# Parse the cmd line arguments
# This implementation is heavily inspired by the following
# stack overflow answer:
# http://stackoverflow.com/questions/26434923/parse-command-line-arguments-in-a-ruby-script
class CmdLineParser
  attr_accessor :args

  USAGE = <<~ENDUSAGE.freeze
    Usage:
      giblish [options] source_dir_top dest_dir_top
  ENDUSAGE
  HELP = <<ENDHELP.freeze
 Options:
  -h --help                  show this help text
  -v --version               show version nr and exit
  -f --format <format>       the output format, currently html5 or pdf are supported
                             *html5* is used if -f is not supplied
  -n --no-build-ref          suppress generation of a reference document at the destination
                             tree root.
  -r --resource-dir <dir>    specify a directory where fonts, themes, css and other
                             central stuff needed for document generation are located.
                             The resources are expected to be located in a subfolder
                             whose name matches the resource type (font, theme
                             or css). If no resource dir is specified, the asciidoctor
                             defaults are used.
  -s --style <name>          The style information used when converting the documents
                             using the -r option for specifying resource directories.
                             For html this is a name of a css file, for pdf, this is
                             the name of an yml file. If no style is given 'giblish'
                             is used as default.
  -w --web-root <path>       Specifies the top dir (DirectoryRoot) of a file system
                             tree published by a web server. This switch is only used
                             when generating html. The typical use case is that giblish
                             is used to generate html docs which are linked to a css.
                             The css link needs to be relative to the top of the web
                             tree (DirectoryRoot on Apache) and not the full absolute
                             path to the css directory.
  -g --git-branches <regExp> if the source_dir_top is located within a git repo,
                             generate docs for all remote branches that matches
                             the given regular expression. Each git branch will
                             be generated to a separate subdir under the destination
                             root dir.
  -t --git-tags <regExp>     if the source_dir_top is located within a git repo,
                             generate docs for all tags that matches the given
                             regular expression. Each tag will be generated to
                             a separate subdir under the destination root dir.
  -c --local-only            do not try to fetch git info from any remotes of the
                             repo before generating documents.
  --log-level                set the log level explicitly. Must be one of
                             debug, info, warn (default), error or fatal.
ENDHELP

  def initialize(cmdline_args)
    parse_cmdline cmdline_args

    # handle help and version requests
    if @args[:help]
      puts HELP
      exit
    end
    if @args[:version]
      puts "Giblish v#{Giblish::VERSION}"
      exit
    end

    # set log level
    set_log_level
    sanity_check_input
    set_gitrepo_root
    # if @args[:logfile]
    #   $stdout.reopen( ARGS[:logfile], "w" )
    #   $stdout.sync = true
    #   $stderr.reopen( $stdout )
    # end
  end

  def usage
    USAGE
  end

  private

  def set_log_level
    log_level = @args[:logLevel] || "warn"
    case log_level
    when "debug" then Giblog.logger.sev_threshold = Logger::DEBUG
    when "info"  then Giblog.logger.sev_threshold = Logger::INFO
    when "warn"  then Giblog.logger.sev_threshold = Logger::WARN
    when "error" then Giblog.logger.sev_threshold = Logger::ERROR
    when "fatal" then Giblog.logger.sev_threshold = Logger::FATAL
    else
      puts "Invalid log level specified. Run with -h to see supported levels"
      puts USAGE
      exit
    end
  end

  def sanity_check_input
    ensure_required_args
    prevent_invalid_combos
  end

  def parse_cmdline(cmdline_args)
    # default values for cmd line switches
    @args = {
      help: false,
      version: false,
      force: true,
      format: "html",
      flatten: false,
      suppressBuildRef: false,
      localRepoOnly: false,
      webRoot: false
    }

    # set default log level
    Giblog.logger.sev_threshold = Logger::WARN

    # defines args without a corresponding flag, the order is important
    unflagged_args = %i[srcDirRoot dstDirRoot]

    # parse cmd line
    next_arg = unflagged_args.first
    cmdline_args.each do |arg|
      case arg
      when "-h", "--help"         then @args[:help]      = true
      when "-v", "--version"      then @args[:version]   = true
      when "-f", "--format   "    then next_arg = :format
      when "-r", "--resource-dir" then next_arg = :resourceDir
      when "-n", "--no-build-ref" then @args[:suppressBuildRef] = true
      when "-g", "--git-branches" then next_arg = :gitBranchRegexp
      when "-t", "--git-tags"     then next_arg = :gitTagRegexp
      when "-c", "--local-only"   then @args[:localRepoOnly] = true
      when "-s", "--style"        then next_arg = :userStyle
      when "-w", "--web-root"     then next_arg = :webRoot
      when "--log-level"            then next_arg = :logLevel
      else
        if next_arg
          @args[next_arg] = arg
          unflagged_args.delete(next_arg)
        end
        next_arg = unflagged_args.first
      end
    end
  end

  def prevent_invalid_combos
    # Prevent contradicting options
    if !@args[:resourceDir] && @args[:userStyle]
      puts "Error: The given style would not be used since no resource dir "\
           "was specified (-s specified without -r)"
    else
      return
    end

    puts USAGE
    exit
  end

  def ensure_required_args
    # Exit if the user does not supply the required arguments
    return unless !@args[:srcDirRoot] || !@args[:dstDirRoot]

    puts "Error: Too few arguments."
    puts USAGE
    exit
  end

  def set_gitrepo_root
    # if user don't want no git repo, we're done
    return unless @args[:gitBranchRegexp] || @args[:gitTagRegexp]

    # The user wants to parse a git repo, check that the srcDirRoot is within a
    # git repo if the user wants to generate git-branch specific docs
    @args[:gitRepoRoot] = Giblish::PathManager.find_gitrepo_root(
      @args[:srcDirRoot]
    )
    return unless @args[:gitRepoRoot].nil?

    # We should not get here if everything is koscher...
    puts "Error: Source dir not in a git working dir despite -g or -t option given!"
    puts USAGE
    exit
  end
end
