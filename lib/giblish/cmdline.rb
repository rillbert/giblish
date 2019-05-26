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
  -f --format <format>       the output format, currently html or pdf are supported
                             *html* is used if -f is not supplied
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
  -i --include <regexp>      include only files with a filename that matches the supplied
                             regexp (defaults to '.*\.(?i)adoc$' meaning it matches all
                             files ending in .adoc case-insensitive). The matching is made
                             on the _file name only_, not the full path (i.e. for the full
                             path /my/file.adoc, only file.adoc is used in the matching).
  -j --exclude <regexp>      exclude files with filenames matching the supplied
                             regexp (no files are excluded by default). The matching is made
                             on the _file name only_, not the full path (i.e. for the full
                             path /my/file.adoc, only file.adoc is used in the matching).
  -w --web-root <path>       Specifies the top dir (DirectoryRoot) of a file system
                             tree published by a web server. This switch is only used
                             when generating html. The typical use case is that giblish
                             is used to generate html docs which are linked to a css.
                             The css link needs to be relative to the top of the web
                             tree (DirectoryRoot on Apache) and not the full absolute
                             path to the css directory.
  -g --git-branches <regExp> if the source_dir_top is located within a git repo,
                             generate docs for all _remote branches on origin_ that matches
                             the given regular expression. Each git branch will
                             be generated to a separate subdir under the destination
                             root dir.
                             NOTE: To do this, giblish will _explicitly check out the
                             matching branches and merge them with the corresponding
                             branch on origin_.
                             NOTE 2: In bash, use double quotes around your regexp if
                             you need to quote it. Single quotes are treated as part
                             of the regexp itself.
  -t --git-tags <regExp>     if the source_dir_top is located within a git repo,
                             generate docs for all tags that matches the given
                             regular expression. Each tag will be generated to
                             a separate subdir under the destination root dir.
  -c --local-only            do not try to fetch git info from any remotes of
                             the repo before generating documents.
  -a --attribute             set a document attribute. The contents of this
                             flag is passed directly to the underlying
                             asciidoctor tool, for details above the syntax,
                             see the man page for asciidoctor. This option can
                             be specified more than once.
  -d --resolve-docid         use two passes, the first to collect :docid:
                             attributes in the doc headers, the second to
                             generate the documents and use the collected
                             doc ids to resolve relative paths between the
                             generated documents
  -m --make-searchable       (only supported for html generation)
                             take steps to make it possible to
                             search the published content via a cgi-script. This
                             flag will do the following:
                               1. index all headings in all source files and store
                                  the result in a JSON file
                               2. copy the JSON file and all source (adoc) files to
                                  a 'search_assets' folder in the top-level dir of
                                  the destination.
                               3. add html code that displays a search field in the
                                  index page that will try to call the cgi-script
                                  'giblish-search' when the user inputs some text.
                             To actually provide search functionality for a user, you
                             need to provide the cgi-script and configure your web-server
                             to invoke it when needed. NOTE: The generated search box cgi
                             is currently hard-coded to look for the cgi script at the URL:
                             http://<your-web-domain>/cgi-bin/giblish-search.cgi
                             E.g.
                             http://example.com/cgi-bin/giblish-search.cgi
                             An implementation of the giblish-search cgi-script is found
                             within the lib folder of this gem, you can copy that to your
                             cgi-bin dir in your webserver and rename it from .rb to .cgi
  --log-level                set the log level explicitly. Must be one of
                             debug, info (default), warn, error or fatal.
ENDHELP

  def initialize(cmdline_args)
    parse_cmdline cmdline_args

    # handle help and version requests
    if @args[:help]
      puts USAGE
      puts ""
      puts HELP
      exit 0
    end
    if @args[:version]
      puts "Giblish v#{Giblish::VERSION}"
      exit 0
    end
  end

  def usage
    USAGE
  end

  private

  def set_log_level
    log_level = @args[:logLevel] || "info"
    case log_level
      when "debug" then Giblog.logger.sev_threshold = Logger::DEBUG
      when "info"  then Giblog.logger.sev_threshold = Logger::INFO
      when "warn"  then Giblog.logger.sev_threshold = Logger::WARN
      when "error" then Giblog.logger.sev_threshold = Logger::ERROR
      when "fatal" then Giblog.logger.sev_threshold = Logger::FATAL
      else
        puts "Invalid log level specified. Run with -h to see supported levels"
        puts USAGE
        exit 1
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
        # note that the single quotes are important for the regexp
        includeRegexp: '.*\.(?i)adoc$',
        excludeRegexp: nil,
        flatten: false,
        suppressBuildRef: false,
        localRepoOnly: false,
        resolveDocid: false,
        make_searchable: false,
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
        when "-i", "--include"      then next_arg = :includeRegexp
        when "-j", "--exclude"      then next_arg = :excludeRegexp
        when "-g", "--git-branches" then next_arg = :gitBranchRegexp
        when "-t", "--git-tags"     then next_arg = :gitTagRegexp
        when "-c", "--local-only"   then @args[:localRepoOnly] = true
        when "-a", "--attribute"    then next_arg = :attributes
        when "-d", "--resolve-docid" then @args[:resolveDocid] = true
        when "-m", "--make-searchable" then @args[:make_searchable] = true
        when "-s", "--style"        then next_arg = :userStyle
        when "-w", "--web-root"     then next_arg = :webRoot
        when "--log-level"          then next_arg = :logLevel
        else
          if next_arg
            if next_arg == :attributes
              # support multiple invocations of -a
              add_attribute arg
            else
              @args[next_arg] = arg
            end
            unflagged_args.delete(next_arg)
          end
          next_arg = unflagged_args.first
      end
    end
  end

  # adds the str (must be in key=value format) to the
  # user defined attributes
  def add_attribute(attrib_str)
    kv = attrib_str.split('=')
    if kv.length != 2
      puts "Invalid attribute format: #{attrib_str} Must be <key>=<value>"
      exit 1
    end

    @args[:attributes] ||= {}
    @args[:attributes][kv[0]] = kv[1]
  end

  def prevent_invalid_combos
    # Prevent contradicting options
    if !@args[:resourceDir] && @args[:userStyle]
      puts "Error: The given style would not be used since no resource dir "\
           "was specified (-s specified without -r)"
    elsif @args[:make_searchable] && @args[:format] != "html"
      puts "Error: The --make-searchable option is only supported for "\
           "html rendering"
    else
      return
    end

    puts USAGE
    exit 1
  end

  def ensure_required_args
    # Exit if the user does not supply the required arguments
    return unless !@args[:srcDirRoot] || !@args[:dstDirRoot]

    puts "Error: Too few arguments."
    puts USAGE
    exit 1
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
    exit 1
  end
end
