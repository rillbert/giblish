require "pathname"

module Giblish
  # returns the paths to the search assets and web assets
  # in the deployment machine's file system.
  class DeploymentPaths
    attr_reader :web_path
    attr_writer :search_assets_path

    def initialize(web_path, search_asset_path)
      @web_path = web_path.nil? ? nil : Pathname.new("/#{web_path}/web_assets").cleanpath
      @search_asset_path = search_asset_path.nil? ? nil : Pathname.new("/#{search_asset_path}").cleanpath
    end

    def search_assets_path(branch_dir = nil)
      branch_dir.nil? ? @search_assets_path : @search_assets_path.join(branch_dir)
    end
  end

  # creates and caches a set of file paths that match the given
  # predicate.
  # after instantiation, the path set is imutable
  #
  # Usage:
  # paths = CachedPathSet(src_root_dir) {|p| your matching predicate here}
  class CachedPathSet
    attr_reader :paths

    def initialize(src_root_dir)
      @paths = []
      src_root = Pathname.new(src_root_dir)
      if src_root.directory?
        Find.find(src_root.realpath.to_s) do |path|
          @paths << Pathname.new(path) if yield(path)
        end
      end
    end
  end

  # Helper class to ease construction of different paths for input and output
  # files and directories
  class PathManager
    attr_reader :src_root_abs, :dst_root_abs, :resource_dir_abs, :search_assets_abs

    # Public:
    #
    # src_root - a string or pathname with the top directory of the input file
    #            tree
    # dst_root - a string or pathname with the top directory of the output file
    #            tree
    # resource_dir - a string or pathname with the directory containing
    #                resources
    # create_search_asset_dir - true if this instance shall create a dir for storing
    #                search artefacts, false otherwise
    def initialize(src_root, dst_root, resource_dir = nil, create_search_asset_dir = false)
      # Make sure that the source root exists in the file system
      @src_root_abs = Pathname.new(src_root).realpath
      self.dst_root_abs = dst_root

      # set the search assets path to its default value
      self.search_assets_abs = @dst_root_abs.join("search_assets") if create_search_asset_dir

      # Make sure that the resource dir exists if user gives a path to it
      resource_dir && (@resource_dir_abs = Pathname.new(resource_dir).realpath)
    end

    def search_assets_abs=(path)
      if path.nil?
        @search_assets_abs = nil
        return
      end

      # create the directory
      dir = Pathname.new(path)
      dir.mkpath
      @search_assets_abs = dir.realpath
    end

    def dst_root_abs=(dst_root)
      # Make sure that the destination root exists and expand it to an
      # absolute path
      Pathname.new(dst_root).mkpath
      @dst_root_abs = Pathname.new(dst_root).realpath
    end

    # Get the relative path from the source root dir to the
    # directory where the supplied path points.
    #
    # in_path:: an absolute or relative path to a file or dir
    def reldir_from_src_root(in_path)
      p = self.class.closest_dir in_path
      p.relative_path_from(@src_root_abs)
    end

    # Get the relative path from the
    # directory where the supplied path points to
    # the src root dir
    #
    # path:: an absolute or relative path to a file or dir
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
    def relpath_to_dir_after_generate(src_filepath, dir_path)
      dst_abs = dst_abs_from_src_abs(src_filepath)
      dir = self.class.to_pathname(dir_path)
      dir.relative_path_from(dst_abs)
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

    # Get the path to the directory where to generate the given
    # file. The path is given as the relative path from the source adoc
    # file to the desired output directory (required by the Asciidoctor
    # API).
    #
    # infile_path:: a string or Pathname containing the absolute path of the
    # source adoc file
    #
    # return:: a Pathname with the relative path from the source file to the
    # output directory
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
      sr = to_pathname(in_path)
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
  end
end
