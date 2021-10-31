require "optparse"
require "logger"

module Giblish
  # parse the cmd line
  class CmdLine
    # Container class for all supported options that are
    # accessible via the cmd line.
    class Options
      attr_accessor :format, :no_index, :index_basename, :graph_basename, :include_regex, :exclude_regex,
        :resource_dir, :style_name, :server_css, :branch_regex, :tag_regex, :local_only, :doc_attributes,
        :resolve_docid, :make_searchable, :search_action_path, :log_level, :srcdir, :dstdir, :web_path

      OUTPUT_FORMATS = ["html", "pdf"]

      LOG_LEVELS = {
        "debug" => Logger::DEBUG,
        "info" => Logger::INFO,
        "warn" => Logger::WARN,
        "error" => Logger::ERROR,
        "fatal" => Logger::FATAL
      }

      def initialize
        @format = OUTPUT_FORMATS[0]
        @publish_type = :local
        @no_index = false
        @index_basename = "index"
        @graph_basename = "gibgraph"
        @include_regex, @exclude_regex = /.*\.(?i)adoc$/, nil
        @resource_dir = nil
        @style_name = nil
        @server_css = nil
        # TODO: remove this soon
        @web_path = nil
        @branch_regex, @tag_regex = nil, nil
        @local_only = false
        @doc_attributes = {}
        @resolve_docid = false
        @make_searchable = false
        @search_action_path = nil
        @log_level = "info"
      end

      def define_options(parser)
        parser.banner = "Usage: #{parser.program_name} [options] srcdir dstdir"
        parser.separator ""
        parser.separator "Converts asciidoc files found under 'srcdir' and store the converted"
        parser.separator "files under 'dstdir'"
        parser.separator ""
        parser.separator "  Options:"

        parser.on("-f", "--format [FORMAT]", OUTPUT_FORMATS,
          "The output format of the converted files",
          "Supported formats are: #{OUTPUT_FORMATS}") do |fmt|
          @format = fmt
        end
        parser.on("-n", "--no-build-ref ", "Suppress generation of indices and",
          "dependency graphs.") do |n|
          @no_index = true
        end
        parser.on("--index-basename ", "Set the basename for generated index files",
          "(default #{@index_basename})") do |name|
          @index_basename = name
        end
        parser.on("-r", "--resource-dir [DIR]",
          "Specify a directory where fonts, themes, css and other",
          "central stuff needed for document generation are located.",
          "The resources are expected to be located in a subfolder",
          "whose name matches the resource type (font, theme",
          "or css). If no resource dir is specified, the asciidoctor",
          "defaults are used. (default: nil)") do |resource_dir|
          r = Pathname.new(resource_dir)
          @resource_dir = (r.absolute? ? r : (Pathname.new(Dir.pwd) / r)).cleanpath
        end
        parser.on("-s", "--style [NAME]",
          "The style information used when converting the documents",
          "using the -r option for specifying resource directories.",
          "For html this is a name of a css file, for pdf, this is",
          "the name of an yml file. You can specify only the",
          "basename of the file and giblish will use the suffix",
          "associated with the output format (i.e specify 'mystyle'",
          "and the mystyle.css and mystyle.yml will be used for html",
          "and pdf generation respectively)",
          "(default: nil -> use default style") do |style_name|
          @style_name = style_name.to_s
        end
        parser.on("-i", "--include [REGEX]",
          "include only files with a path that matches the supplied",
          "regexp (defaults to #{@include_regex} meaning it matches all",
          "files ending in .adoc case-insensitive). The matching is made",
          "on the full path (i.e. the regex '^.*my.*' matches the path",
          "/my/file.adoc).") do |regex_str|
          @include_regex = Regexp.new(regex_str)
        end
        parser.on("-j", "--exclude [REGEX]",
          "exclude files with a path that matches the supplied",
          "regexp (no files are excluded by default). The matching is made",
          "on the full path (i.e. the regex '^.*my.*' matches the path",
          "/my/file.adoc).") do |regex_str|
          @exclude_regex = Regexp.new(regex_str)
        end
        parser.on("-w", "--web-path [PATH]",
          "DEPRECATED!! You should use the server-search-path and",
          "server-css-path flags instead.") do |path|
          Giblog.logger.error { "The '-w' flag is DEPRECATED, use the '--server-search-path' and '--server-css-path' flags instead." }
          @web_path = true
        end
        parser.on("--server-css-path [PATH]",
          "Sets a specific path to the stylesheet used by the generated",
          "html documents. This flag can be used instead of the 's' and",
          "'r' flags if a pre-existing stylesheet exists at a known",
          "location that is accessible from the generated documents via",
          "an 'href' element.",
          "This flag is only used for html generation.") do |path|
          @server_css = Pathname.new(path)
        end
        parser.on("-g", "--git-branches [REGEX]",
          "if the source_dir_top is located within a git repo,",
          "generate docs for all _remote branches on origin_ that matches",
          "the given regular expression. Each git branch will",
          "be generated to a separate subdir under the destination",
          "root dir.",
          "NOTE: To do this, giblish will _explicitly check out the",
          "matching branches and merge them with the corresponding",
          "branch on origin_.",
          "NOTE 2: In bash, use double quotes around your regexp if",
          "you need to quote it. Single quotes are treated as part",
          "of the regexp itself.") do |regex_str|
            @branch_regex = Regexp.new(regex_str)
          end
        parser.on("-t", "--git-tags [REGEX]",
          "if the source_dir_top is located within a git repo,",
          "generate docs for all tags that matches the given",
          "regular expression. Each tag will be generated to",
          "a separate subdir under the destination root dir.") do |regex_str|
            @tag_regex = Regexp.new(regex_str)
          end
        parser.on("-c", "--local-only",
          "do not try to fetch git info from any remotes of",
          "the repo before generating documents.") do |local_only|
            @local_only = true
          end
        parser.on("-a", "--attribute [KEY=VALUE]",
          "set a document or asciidoctor attribute.",
          "The contents of this flag is passed directly to the",
          "underlying asciidoctor tool, for details above the",
          "syntax and available attributes, see the documentation for",
          "asciidoctor. This option can be specified more than once.") do |attr_str|
          tokens = attr_str.split("=")
          raise OptionParser::InvalidArgument, "Document attributs must be specified as 'key=value'!" unless tokens.count == 2
          @doc_attributes[tokens[0]] = tokens[1]
        end
        parser.on("-d", "--resolve-docid",
          "Collect document ids in the form of :docid:",
          "attributes in the doc headers. Use these ids to",
          "resolve cross-references of docid:s from one document",
          "to another.") do |d|
          @resolve_docid = d
        end
        parser.on("-m", "--make-searchable",
          "(only supported for html generation)",
          "take steps to make it possible to search the generated",
          "docs via the web server through which they are published.",
          "This flag will do the following:",
          "  1. index all headings in all source files and store",
          "     the result in a JSON file",
          "  2. copy the JSON file and all source (adoc) files to",
          "     a 'search_assets' folder in the top-level dir of",
          "     the destination.",
          "  3. add html/javascript code that displays a search form",
          "     at the top of the generated documents. The search form",
          "     sends a html POST to the path specified with the ",
          "     'server-search-path' flag when the user inputs some text.",
          "To actually provide search functionality for readers, you",
          "need to provide a server side script or application that can",
          "respond to the html POST and return relevant info.",
          "giblish contains most of the functionality for this and an",
          "implementation of a cgi-script is bundled with this gem.") do |m|
          @make_searchable = m
        end
        parser.on("--server-search-path URLPATH",
          "the url path to which search requests are sent.",
          "(default is #{@search_action_path}).",
          "E.g.",
          "If the search script resides under 'www.mysite.com/actions/gibsearch'",
          "you would set this as '--server-search-path /actions/gibsearch'") do |p|
          @search_action_path = Pathname.new(p)
        end
        parser.on("-l", "--log-level LEVEL", LOG_LEVELS,
          "set the log level explicitly. Must be one of",
          LOG_LEVELS.keys.join(",").to_s, "(default 'info')") do |level|
          @log_level = level
        end
        parser.on_tail("-h", "--help", "Show this message") do
          puts parser
          exit 0
        end
        parser.on_tail("-v", "--version", "Show version") do
          puts "Giblish v#{Giblish::VERSION}"
          exit 0
        end
      end

      # enable pattern matching of instances as if they were
      # a hash
      def deconstruct_keys(keys)
        h = {}
        instance_variables.each do |v|
          value = instance_variable_get(v)
          h[v[1..].to_sym] = value unless value.nil?
        end
        h
      end
    end

    # converts the given cmd line args to an Options instance.
    #
    # Raises MissingArgument or InvalidArgument if the cmd line arg
    # validation fails.
    #
    # === Returns
    # the option instance corresponding to the given cmd line args
    def parse(args)
      @cmd_opts = Options.new
      @args = OptionParser.new do |parser|
        @cmd_opts.define_options(parser)
        parser.parse!(args)

        # take care of positional arguments
        raise OptionParser::MissingArgument, "Both srcdir and dstdir must be provided!" unless args.count == 2

        # we always work with absolute paths
        @cmd_opts.srcdir, @cmd_opts.dstdir = [args[0], args[1]].collect do |arg|
          d = Pathname.new(arg)
          d = Pathname.new(Dir.pwd) / d unless d.absolute?
          d.cleanpath
        end

        validate_options(@cmd_opts)
      end
      @cmd_opts
    end

    private

    # Raise InvalidArgument if an unsupported cmd line combo is
    # discovered
    def validate_options(opts)
      raise OptionParser::InvalidArgument, "Could not find source path #{opts.srcdir}" unless opts.srcdir.exist?

      if opts.web_path
        raise OptionParser::InvalidArgument, "The '-w/--web-path' flag is DEPRECATED. Use the --server-css-path and --server--search-path flags instead."
      end

      if opts.server_css && (opts.resource_dir || opts.style_name)
        raise OptionParser::InvalidArgument, "The '-w' flag can not be used with either of the '-r' or '-s' flags"
      end

      if opts.server_css && opts.format != "html"
        raise OptionParser::InvalidArgument, "The '-w' flag can only be used for the 'html' format flags"
      end

      if opts.resource_dir.nil? ^ opts.style_name.nil?
        raise OptionParser::InvalidArgument, "Either both '-s' and '-r' flags must be given or none of them."
      end

      if opts.resource_dir && !opts.resource_dir.exist?
        raise OptionParser::InvalidArgument, "Could not find resource path #{opts.resource_dir}"
      end

      if opts.make_searchable && opts.format != "html"
        raise OptionParser::InvalidArgument, "Error: The --make-searchable option "\
        "is only supported for html rendering."
      end

      if opts.search_action_path && !opts.make_searchable
        raise OptionParser::InvalidArgument, "Error: The --server-search-path "\
        "flag is only supported in combination with the --make-searchable (-m) flag."
      end
    end
  end
end
