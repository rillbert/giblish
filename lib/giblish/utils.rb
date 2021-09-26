require "logger"
require "pathname"
require "fileutils"
require "find"

# The logger used from within giblish
class Giblog
  # Defines the format for log messages from giblish.
  class GiblogFormatter
    def call(severity, datetime, _progname, msg)
      "#{datetime.strftime("%H:%M:%S")} #{severity} - #{msg}\n"
    end
  end

  # bootstrap the application-wide logger object
  def self.setup
    return if defined? @logger

    @logger = Logger.new($stdout)
    @logger.formatter = GiblogFormatter.new
  end

  # returns the application-wide logger instance.
  def self.logger
    unless defined? @logger
      puts "!!!! Error: Trying to access logger before setup !!!!"
      puts caller
      exit
    end
    @logger
  end
end

# Public: Contains a number of generic utility methods.
module Giblish
  # This logger is customized to receive log messages via the Asciidoctor API.
  # It parses the messages and 'source_location' objects from the Asciidoctor API
  # into messages using an opinionated format.
  #
  # The output is written to both $stdout and an in-memory StringIO instance. The log level
  # can be set separately for each of these output channels.
  class AsciidoctorLogger < ::Logger
    attr_reader :max_severity, :in_mem_storage

    # log formatter specialized for formatting messages from
    # asciidoctor's stdout, handles the different log record types that Asciidoctor
    # emits
    class UserInfoFormatter
      SEVERITY_LABELS = {"WARN" => "WARNING", "FATAL" => "FAILED"}.freeze

      # The hash that can be emitted as the msg from asciidoctor have the
      # following format:
      # {:text=>"...",
      #  :source_location=>#<Asciidoctor::Reader::Cursor:0x000055e65a8729e0
      #          @file="<full adoc filename>",
      #          @dir="<full src dir>",
      #          @path="<only file name>",
      #          @lineno=<src line no>
      # }
      def call(severity, datetime, progname, msg)
        message = case msg
                  when ::String
                    msg
                  when ::Hash
                    # asciidoctor seem to emit a hash with the following structure on errors:
                    # :text => String
                    # :source_location => Reader::Cursor with the following props:
                    #   dir, file, lineno, path
                    # Only the lineno prop can be trusted when Asciidoctor is used via Giblish
                    #
                    src_loc = msg.fetch(:source_location, nil)
                    err_txt = msg.fetch(:text, "")
                    str = +""
                    str << "Line #{src_loc.lineno} - " if src_loc.lineno
                    str << err_txt
                    str
                  else
                    msg.inspect
        end
        %(#{datetime.strftime("%H:%M:%S")} #{progname}: #{SEVERITY_LABELS[severity] || severity}: #{message}\n)
      end
    end

    # The level is one of the standard ::Logger levels
    #
    # stdout_level:: the log level to use for gating the messages to stdout
    # string_level:: the log level to use for gating the messages to the in-memory string.
    # defaults to 'stdout_level' if not set.
    def initialize(stdout_level, string_level = nil)
      super($stdout, progname: "(asciidoctor)", formatter: UserInfoFormatter.new, level: stdout_level)
      string_level = stdout_level if string_level.nil?

      @max_severity = UNKNOWN

      # create a new, internal logger that echos messages to an in-memory string
      @in_mem_storage = StringIO.new
      @in_mem_logger = ::Logger.new(@in_mem_storage, formatter: UserInfoFormatter.new, level: string_level)
    end

    def add(severity, message = nil, progname = nil)
      # update the maximum severity received by this logger
      @max_severity = severity if severity != UNKNOWN && severity > @max_severity

      # write the log message to both channels
      @in_mem_logger.add(severity, message, progname)
      super
    end
  end

  # Helper method that provides the user with a way of processing only the
  # lines within the asciidoc header block.
  # The user must return nil to get the next line.
  #
  # ex:
  # process_header_lines(file_path) do |line|
  #   if line == "Quack!"
  #      myvar = "Donald!"
  #      1
  #   else
  #      nil
  #   end
  # end
  def process_header_lines(lines, &block)
    return unless block

    state = "before_header"
    lines.each do |line|
      case state
      when "before_header" then (state = "in_header" if line =~ /^[=+]^.*$/ || yield(line))
      when "in_header" then (state = "done" if line =~ /^\s*$/ || yield(line))
      when "done" then break
      end
    end
  end
  module_function :process_header_lines

  # Helper method that provides the user with a way of processing only the
  # lines within the asciidoc header block.
  # The user must return nil to get the next line.
  #
  # ex:
  # process_header_lines_from_file(file_path) do |line|
  #   if line == "Quack!"
  #      myvar = "Donald!"
  #      1
  #   else
  #      nil
  #   end
  # end
  def process_header_lines_from_file(path, &block)
    return unless block

    lines = File.readlines(path)
    process_header_lines(lines, &block)
  end
  module_function :process_header_lines_from_file

  # runs the supplied block but redirect stderr to a string
  # returns the string containing stderr contents
  def with_captured_stderr
    old_stderr = $stderr
    $stderr = StringIO.new("", "w")
    yield
    $stderr.string
  ensure
    $stderr = old_stderr
  end
  module_function :with_captured_stderr

  # transforms strings to valid asciidoctor id strings
  def to_valid_id(input_str, id_prefix = "_", id_separator = "_")
    id_str = input_str.strip.downcase.gsub(/[^a-z0-9]+/, id_separator)
    id_str = "#{id_prefix}#{id_str}"
    id_str.chomp(id_separator)
  end
  module_function :to_valid_id

  # See https://stackoverflow.com/questions/2108727/which-in-ruby-checking-if-program-exists-in-path-from-ruby
  # Cross-platform way of finding an executable in the $PATH.
  #
  # Ex
  #   which('ruby') #=> /usr/bin/ruby
  def which(cmd)
    exts = ENV["PATHEXT"] ? ENV["PATHEXT"].split(";") : [""]
    ENV["PATH"].split(File::PATH_SEPARATOR).each do |path|
      exts.each do |ext|
        exe = File.join(path, "#{cmd}#{ext}")
        return exe if File.executable?(exe) && !File.directory?(exe)
      end
    end
    nil
  end
  module_function :which

  # returns raw html that displays a search box to let the user
  # acces the text search functionality.
  #
  # css          - the name of the css file to use for the search result layout
  # cgi_path     - the (uri) path to a cgi script that implements the server side
  #                functionality of searching the text
  # opts:
  # :web_assets_top => string   # the path to the 'web_assets' dir as seen when serving
  #                               the web server (eg www.mysite.com/blah/doc_root ->
  #                               web_assets_top shall be '/blah/doc_root')
  # :search_assets_top => string   # the path to where the 'heading.json' file is located (
  #                                  as seen from the local file system on the machine that
  #                                  runs the search script)
  def generate_search_box_html(css, cgi_path, opts)
    # Replace the button with the below to use a text-only version of the btn
    # <button id="search" type="submit">Search</button>
    <<~SEARCH_INFO
      ++++
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.min.css">
        <form class="example" action="#{cgi_path}" style="margin:20px 0px 20px 0px;max-width:790px">
            Search all documents:
            <input id="searchphrase" type="text" placeholder="Search.." name="searchphrase"/>
            <button id="search" type="submit"><i class="fa fa-search"></i></button>
            <br>

            <input id="ignorecase" type="checkbox" value="true" name="ignorecase" checked/>
            <label for="ignorecase">Ignore Case</label>
            &nbsp;&nbsp;
            <input id="useregexp" type="checkbox" value="true" name="useregexp"/>
            <label for="useregexp">Use Regexp</label>

            <input type="hidden" name="searchassetstop" value="#{opts[:search_assets_top]}"</input>
            <input type="hidden" name="webassetstop" value="#{opts[:web_assets_top]}"</input>
            #{%(<input type="hidden" name="css" value="#{css}"</input>) unless css.nil?}
        </form>
      ++++

    SEARCH_INFO
  end
  module_function :generate_search_box_html

  # Convert a string into a string where all characters forbidden as part of
  # filenames are replaced by an underscore '_'.
  #
  # returns:: a String most likely a valid filename in windows & linux
  #
  # A comprehensive list of forbidden chars in different file systems can be
  # found here: https://stackoverflow.com/a/31976060
  # In short, chars forbidden in any of Windows and Linux are:
  # / < > : " \\ | ? *
  def to_fs_str(str)
    # printable chars -> '_'
    tmp = str.gsub(/[\/<>:"\\|?*]/, "_")
    # non-printable chars -> '_'
    tmp.gsub!(/[\x00-\x1F]/,'_')
    # remove heading/trailing spaces
    tmp.strip!
    # Windows disallows files ending in '.'
    tmp += "_" if tmp.end_with?(".")

    tmp
  end
  module_function :to_fs_str
end
