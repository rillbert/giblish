require "logger"
require "pathname"
require "fileutils"

class Giblog
  def self.setup
    return if defined? @logger
    @logger = Logger.new(STDOUT)
    @logger.formatter = proc do |severity, datetime, _progname, msg|
      "#{datetime.strftime('%H:%M:%S')} #{severity} - #{msg}\n"
    end
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
  # Helper class to ease construction of different paths for input and output
  # files and directories
  class PathManager
    attr_reader :src_root_abs
    attr_reader :dst_root_abs
    attr_reader :resource_dir_abs

    # Public:
    #
    # src_root - a string or pathname with the top directory of the input file
    #            tree
    # dst_root - a string or pathname with the top directory of the output file
    #            tree
    # resource_dir - a string or pathname with the directory containing
    #                resources
    def initialize(src_root, dst_root, resource_dir = nil)
      # Make sure that the source root exists in the file system
      @src_root_abs = Pathname.new(src_root).realpath
      self.dst_root_abs = dst_root
      # Make sure that the resource dir exists if user gives a path to it
      resource_dir && (@resource_dir_abs = Pathname.new(resource_dir).realpath)
    end

    def dst_root_abs=(dst_root)
      # Make sure that the destination root exists and expand it to an
      # absolute path
      Pathname.new(dst_root).mkpath
      @dst_root_abs = Pathname.new(dst_root).realpath
    end

    # Public: Get the relative path from the source root dir to the
    #         source file dir.
    #
    # in_path - an absolute or relative path
    def reldir_from_src_root(in_path)
      p = in_path.is_a?(Pathname) ? in_path : Pathname.new(in_path)

      # Get absolute source dir path
      src_abs = p.directory? ? p.realpath : p.dirname.realpath

      # Get relative path from source root dir
      src_abs.relative_path_from(@src_root_abs)
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
      sr = in_path.is_a?(Pathname) ? in_path : Pathname.new(in_path)
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
      Pathname.new(dirpath).expand_path.ascend do |p|
        git_dir = p.join(".git")
        return p if git_dir.directory?
      end
    end
  end

  def with_captured_stderr
    old_stderr = $stderr
    $stderr = StringIO.new("", "w")
    yield
    $stderr.string
  ensure
    $stderr = old_stderr
  end
  module_function :with_captured_stderr

  def to_valid_id(input_str)
    id_str = "_#{input_str.downcase}"
    id_str.gsub(%r{[^a-z0-9]+},"_")
  end
  module_function :to_valid_id
end
