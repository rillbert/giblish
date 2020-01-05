require "logger"
require "pathname"
require "fileutils"

class GiblogFormatter
  def call severity, datetime, progname, msg
    "#{datetime.strftime('%H:%M:%S')} #{severity} - #{msg}\n"
  end
end

class Giblog
  def self.setup
    return if defined? @logger
    @logger = Logger.new(STDOUT)
    @logger.formatter = GiblogFormatter.new
    # @logger.formatter = proc do |severity, datetime, _progname, msg|
    #   "#{datetime.strftime('%H:%M:%S')} #{severity} - #{msg}\n"
    # end
  end

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

  class UserInfoFormatter
    SEVERITY_LABELS = { 'WARN' => 'WARNING', 'FATAL' => 'FAILED' }

    # {:text=>"...",
    #  :source_location=>#<Asciidoctor::Reader::Cursor:0x000055e65a8729e0
    #          @file="<full adoc filename>",
    #          @dir="<full src dir>",
    #          @path="<only file name>",
    #          @lineno=<src line no>
    # }
    def call severity, datetime, progname, msg
      message = case msg
                when ::String
                  msg
                when ::Hash
                  # asciidoctor seem to emit a hash with error text and source location info
                  # for warnings and errors
                  str = ""
                  str << "Line #{msg[:source_location].lineno.to_s} - " if msg[:source_location]
                  str << "#{msg[:text].to_s}" if msg[:text]
                  str
                else
                  msg.inspect
                end
      %(#{datetime.strftime('%H:%M:%S')} #{progname}: #{SEVERITY_LABELS[severity] || severity}: #{message}\n)
    end
  end
  class AsciidoctorLogger < ::Logger

    attr_reader :max_severity
    attr_reader :user_info_str

    def initialize user_info_log_level
      super(STDOUT,progname: "(from asciidoctor)", formatter: UserInfoFormatter.new)
      @user_info_str = StringIO.new
      @user_info_logger = ::Logger.new(@user_info_str, formatter: UserInfoFormatter.new, level: user_info_log_level)
    end

    def add severity, message = nil, progname = nil
      if (severity ||= UNKNOWN) > (@max_severity ||= severity)
        @max_severity = severity
      end
      @user_info_logger.add(severity,message,progname)
      super
    end
  end

  # Helper class to ease construction of different paths for input and output
  # files and directories
  class PathManager
    attr_reader :src_root_abs
    attr_reader :dst_root_abs
    attr_reader :resource_dir_abs
    attr_reader :web_root_abs

    # Public:
    #
    # src_root - a string or pathname with the top directory of the input file
    #            tree
    # dst_root - a string or pathname with the top directory of the output file
    #            tree
    # resource_dir - a string or pathname with the directory containing
    #                resources
    def initialize(src_root, dst_root, resource_dir = nil, web_root = nil)
      # Make sure that the source root exists in the file system
      @src_root_abs = Pathname.new(src_root).realpath
      self.dst_root_abs = dst_root

      # Make sure that the resource dir exists if user gives a path to it
      resource_dir && (@resource_dir_abs = Pathname.new(resource_dir).realpath)

      # Set web root if given by user
      @web_root_abs = nil
      if web_root
        web_root = "/" + web_root unless web_root[0] == '/'
        @web_root_abs = web_root ? Pathname.new(web_root) : nil
      end
    end

    def dst_root_abs=(dst_root)
      # Make sure that the destination root exists and expand it to an
      # absolute path
      Pathname.new(dst_root).mkpath
      @dst_root_abs = Pathname.new(dst_root).realpath
    end

    # Public: Get the relative path from the source root dir to the
    #         directory where the supplied path points.
    #
    # in_path - an absolute or relative path to a file or dir
    def reldir_from_src_root(in_path)
      p = self.class.closest_dir in_path
      p.relative_path_from(@src_root_abs)
    end

    # Public: Get the relative path from the
    #         directory where the supplied path points to
    #         the src root dir
    #
    # path - an absolute or relative path to a file or dir
    def reldir_to_src_root(path)
      src = self.class.closest_dir path
      @src_root_abs.relative_path_from(src)
    end

    # Public: Get the relative path from the dst root dir to the
    #         directory where the supplied path points.
    #
    # path - an absolute or relative path to a file or dir
    def reldir_from_dst_root(path)
      dst = self.class.closest_dir path
      dst.relative_path_from(@dst_root_abs)
    end

    # Public: Get the relative path from the
    #         directory where the supplied path points to
    #         the dst root dir
    #
    # path - an absolute or relative path to a file or dir
    def reldir_to_dst_root(path)
      dst = self.class.closest_dir path
      @dst_root_abs.relative_path_from(dst)
    end

    # return the destination dir corresponding to the given src path
    # the src path must exist in the file system
    def dst_abs_from_src_abs(src_path)
      src_abs = (self.class.to_pathname src_path).realpath
      src_rel = reldir_from_src_root src_abs
      @dst_root_abs.join(src_rel)
    end

    # return the relative path from a generated document to
    # the supplied folder given the corresponding absolute source
    # file path
    def relpath_to_dir_after_generate(src_filepath,dir_path)
      dst_abs = dst_abs_from_src_abs(src_filepath)
      dir = self.class.to_pathname(dir_path)
      dir.relative_path_from(dst_abs)
    end

    def reldir_from_web_root(path)
      p = self.class.closest_dir path
      return p if @web_root_abs.nil?
      p.relative_path_from(@web_root_abs)
    end

    def reldir_to_web_root(path)
      p = self.class.closest_dir path
      return p if @web_root_abs.nil?
      @web_root_abs.relative_path_from(p)
    end

    def adoc_output_file(infile_path, extension)
      # Get absolute source dir path
      src_dir_abs = self.class.closest_dir infile_path

      # Get relative path from source root dir
      src_dir_rel = src_dir_abs.relative_path_from(@src_root_abs)

      # Get the destination path relative the absolute source
      # root
      dst_dir_abs = @dst_root_abs.realpath.join(src_dir_rel)

      # return full file path with correct extension
      dst_dir_abs + get_new_basename(infile_path, extension)
    end

    # Public: Get the path to the directory where to generate the given
    #         file. The path is given as the relative path from the source adoc
    #         file to the desired output directory (required by the Asciidoctor
    #         API).
    #
    # infile_path - a string or Pathname containing the absolute path of the
    #               source adoc file
    #
    # Returns: a Pathname with the relative path from the source file to the
    #          output directory
    def adoc_output_dir(infile_path)
      # Get absolute source dir path
      src_abs = self.class.closest_dir infile_path

      # Get relative path from source root dir
      src_rel = src_abs.relative_path_from(@src_root_abs)

      # Get the destination path relative the absolute source
      # root
      dst_abs = @dst_root_abs.realpath.join(src_rel)
      dst_abs.relative_path_from(src_abs)
    end

    # return a pathname, regardless if the given path is a Pathname or
    # a string
    def self.to_pathname(path)
      path.is_a?(Pathname) ? path : Pathname.new(path)
    end

    # Public: Get the basename for a file by replacing the file
    #         extention of the source file with the supplied one.
    #
    # src_filepath - the full path of the source file
    # file_ext - the file extention of the resulting file name
    #
    # Example
    #
    # Giblish::PathManager.get_new_basename(
    #  "/my/old/file.txt","pdf") => "file.pdf"
    #
    # Returns: the basename of a file that uses the supplied file extention.
    def self.get_new_basename(src_filepath, file_ext)
      p = Pathname.new src_filepath
      newname = p.basename.to_s.reverse.sub(p.extname.reverse, ".").reverse
      newname << file_ext
    end

    # Public: Return the absolute path to the closest directory (defined as
    #          - the parent dir when called with an existing file
    #          - the directory itself when called with an existing directory
    #          - the parent dir when called with a non-existing file/directory
    def self.closest_dir(in_path)
      sr = self.to_pathname(in_path)
      if sr.exist?
        sr.directory? ? sr.realpath : sr.dirname.realpath
      else
        sr.parent.expand_path
      end
    end

    # Public: Find the root directory of the git repo in which the
    #         given dirpath resides.
    #
    # dirpath - a relative or absolute path to a directory that resides
    #           within a git repo.
    #
    # Returns: the root direcotry of the git repo or nil if the input path
    #          does not reside within a git repo.
    def self.find_gitrepo_root(dirpath)
      Pathname.new(dirpath).realpath.ascend do |p|
        git_dir = p.join(".git")
        return p if git_dir.directory?
      end
    end
  end # end of PathManager

  # Helper method that provides the user with a way of processing only the
  # lines within the asciidoc header block.
  # The user must return nil to get the next line.
  #
  # ex:
  # process_header_lines(file_path) do |line|
  #   if line == "Quack!"
  #      puts "Donald!"
  #      1
  #   else
  #      nil
  #   end
  # end
  def process_header_lines(lines)
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
  #      puts "Donald!"
  #      1
  #   else
  #      nil
  #   end
  # end
  def process_header_lines_from_file(path)
    lines = File.readlines(path)
    process_header_lines(lines,&Proc.new)
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
  def to_valid_id(input_str,id_prefix="_", id_separator="_")
    id_str = input_str.strip.downcase.gsub(%r{[^a-z0-9]+}, id_separator)
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
    exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
    ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
      exts.each { |ext|
        exe = File.join(path, "#{cmd}#{ext}")
        return exe if File.executable?(exe) && !File.directory?(exe)
      }
    end
    return nil
  end
  module_function :which


  # returns raw html that displays a search box to let the user
  # acces the text search functionality.
  #
  # css          - the name of the css file to use for the search result layout
  # cgi_path     - the (uri) path to a cgi script that implements the server side
  #                functionality of searching the text
  # opts:
  # :topdir => string     # the absolute filesystem path to the root dir of the generated docs
  # :reltop => string     # the relative path to the directory containing the 'web_assets' dir
  # :branch_dir => string # the name of the top directory for the rendered
  #                         git branch/tag or nil if no git repo is used.
  def generate_search_box_html(css, cgi_path, opts)

    # button with magnifying glass icon (not working when deployed)
    # <button id="search" type="submit"><i class="fa fa-search"></i></button>
    <<~SEARCH_INFO
      ++++
        <form class="example" action="#{cgi_path}" style="margin:20px 0px 20px 0px;max-width:380px">
            Search all documents: 
            <input id="searchphrase" type="text" placeholder="Search.." name="searchphrase"/>
            <button id="search" type="submit">Search</button>
            <br>

            <input id="ignorecase" type="checkbox" value="true" name="ignorecase" checked/>
            <label for="ignorecase">Ignore Case</label>
            &nbsp;&nbsp;
            <input id="useregexp" type="checkbox" value="true" name="useregexp"/>
            <label for="useregexp">Use Regexp</label>

            <input type="hidden" name="reltop" value="#{opts[:reltop]}"</input>
            <input type="hidden" name="css" value="#{css}"</input>

            <input type="hidden" name="topdir" value="#{opts[:topdir]}"</input>
            <input type="hidden" name="branchdir" value="#{opts[:branch_dir]}"</input>
        </form>
      ++++

    SEARCH_INFO
  end
  module_function :generate_search_box_html

end
