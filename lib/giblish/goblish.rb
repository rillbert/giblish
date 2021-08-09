require "optparse"

module Giblish
  # parse the cmd line
  class CmdLine
    class Options
      attr_accessor :format, :no_index, :index_basename, :include_regex, :exclude_regex,
        :resource_dir, :style_name, :web_path, :branch_regex, :tag_regex, :doc_attributes,
        :resolve_docid, :log_level, :srcdir, :dstdir

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
        @no_index, @index_basename = false, "index"
        @include_regex, @exclude_regex = /.*\.(?i)adoc$/, nil
        @resource_dir = Pathname.getwd
        @style_name = "giblish"
        @web_path = nil
        @branch_regex, @tag_regex = nil, nil
        @doc_attributes = {}
        @resolve_docid = false
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
        parser.on("-n", "--no-build-ref ", "Suppress index generation") do |n|
          @no_index = n
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
          "defaults are used. (default: #{@resource_dir})") do |resource_dir|
          @resource_dir = Pathname.new(resource_dir)
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
          "(default: #{@style_name})") do |style_name|
          @style_name = style_name.to_s
        end
        parser.on("-i", "--include [REGEX]",
          "include only files with a path that matches the supplied",
          "regexp (defaults to #{@include_regex} meaning it matches all",
          "files ending in .adoc case-insensitive). The matching is made",
          "on the full path (i.e. the regex '^.*my.*' matches the path",
          "/my/file.adoc).") do |regex_str|
          @include_regex = Regex.new(regex_str)
        end
        parser.on("-j", "--exclude [REGEX]",
          "exclude files with a path that matches the supplied",
          "regexp (no files are excluded by default). The matching is made",
          "on the full path (i.e. the regex '^.*my.*' matches the path",
          "/my/file.adoc).") do |regex_str|
          @exclude_regex = Regex.new(regex_str)
        end
        parser.on("-w", "--web-path [PATH]",
          "Specifies the URL path to where the generated html documents",
          "will be deployed (only needed when serving the html docs via",
          "a web server).",
          "E.g.",
          "If the docs are deployed to 'www.example.com/site_1/blah',",
          "this flag shall be set to '/site_1/blah'. This switch is only",
          "used when generating html. giblish use this to link the deployed",
          "html docs with the correct stylesheet.") do |path|
          @web_path = Pathname.new(path)
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
            @branch_regex = Regex.new(regex_str)
          end
        parser.on("-t", "--git-tags [REGEX]",
          "if the source_dir_top is located within a git repo,",
          "generate docs for all tags that matches the given",
          "regular expression. Each tag will be generated to",
          "a separate subdir under the destination root dir.") do |regex_str|
            @tag_regex = Regex.new(regex_str)
          end
        parser.on("-c", "--local-only",
          "do not try to fetch git info from any remotes of",
          "the repo before generating documents.") do |local_only|
            @local_only = local_only
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
          "use two passes, the first to collect :docid:",
          "attributes in the doc headers, the second to",
          "generate the documents and use the collected",
          "doc ids to resolve relative paths between the",
          "generated documents") do |d|
          @resolve_docid = d
        end
        parser.on("--log-level LEVEL", LOG_LEVELS,
          "set the log level explicitly. Must be one of",
          LOG_LEVELS.keys.join(",").to_s,"(default 'info')") do |level|
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
    end

    def parse(args)
      # The options specified on the command line will be collected in
      # *options*.

      @cmdline = Options.new
      @args = OptionParser.new do |parser|
        @cmdline.define_options(parser)
        parser.parse!(args)

        # take care of positional arguments
        raise OptionParser::MissingArgument, "Both srcdir and dstdir must be provided!" unless args.count == 2

        @cmdline.srcdir = Pathname.new(args[0])
        @cmdline.dstdir = Pathname.new(args[1])
      end
      @cmdline
    end
  end
end
