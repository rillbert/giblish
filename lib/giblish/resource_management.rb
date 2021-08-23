module Giblish
  # Provides relevant paths for layout resources based on the given options
  class ResourcePaths
    STYLE_EXTENSIONS = {
      "html5" => ".css",
      "html" => ".css",
      "pdf" => ".yml",
      "web-pdf" => ".css"
    }

    FONT_REGEX = /.*\.(ttf)|(TTF)$/
    RESOURCE_DST_TOP_BASENAME = Pathname.new("web_assets")

    # the relative path from the top of the resource area to the 
    # style file
    attr_reader :src_style_path_rel

    # the absolute path from the top of the resource area to the 
    # style file
    attr_reader :src_style_path_abs

    # a set with all dirs containing ttf files, paths are relative to resource area top
    attr_reader :font_dirs_abs

    # the relative path from the dst top dir to the copied style file (if it would be copied)
    attr_reader :dst_style_path_rel

    # the abs path to the top of the destination dir for resources
    attr_reader :dst_resource_dir_abs

    def initialize(cmd_opts)
      @style_ext = STYLE_EXTENSIONS.fetch(cmd_opts.format, nil)
      raise OptionParser::InvalidArgument, "Unsupported format: #{cmd_opts.format}" if @style_ext.nil?

      # Cache all file paths in the resource area
      r_top = cmd_opts.resource_dir
      file_tree = PathTree.build_from_fs(r_top)

      # find and validate paths
      @dst_resource_dir_abs = cmd_opts.dstdir / RESOURCE_DST_TOP_BASENAME
      @src_style_path_rel = find_style_file(file_tree, cmd_opts)
      @src_style_path_abs = r_top / @src_style_path_rel
      @dst_style_path_rel = RESOURCE_DST_TOP_BASENAME / @src_style_path_rel
      @font_dirs_abs = find_font_dirs(file_tree)
    end

    private

    # returns:: the relative path from the top of the file_tree to
    # the style file
    def find_style_file(file_tree, cmd_opts)

      # Get all files matching the style name
      style_basename = Pathname.new(cmd_opts.style_name).sub_ext(@style_ext)
      style_tree = file_tree.match(/.*#{style_basename}$/)

      # make sure we have exactly one css file with the given name
      raise OptionParser::InvalidArgument, "Did not find #{style_basename} under #{file_tree.pathname}" if style_tree.nil?

      l = style_tree.leave_pathnames(prune: true)
      if l.count > 1
        raise OptionParser::InvalidArgument, "Found #{l.count} instances of #{style_basename} under #{file_tree.pathname}. Requires exactly one."
      end

      # return the (pruned) path
      l[0]
    end

    def find_font_dirs(file_tree)
      tree = file_tree.match(FONT_REGEX)
      dirs = Set.new
      tree&.traverse_preorder do |level, node|
        next unless node.leaf?

        dirs << node.pathname.dirname
      end
      dirs
    end
  end

  # copy everything under cmd_opts.resource_dir to
  # dst_top/web_assets/.
  class CopyResourcesPreBuild
    # required opts:
    # resource_dir:: Pathname to the top of the resource area to be copied
    # style_name:: basename of the css to use for styling
    # dstdir:: Pathname to the destination dir where the copied resources will be
    # stored.
    def initialize(cmd_opts)
      @opts = cmd_opts.dup
      @paths = ResourcePaths.new(cmd_opts)
    end

    def run(src_tree, dst_tree, converter)
      copy_resource_area(@opts)
    end

    private

    # copy everyting under cmd_opts.resource_dir to @web_asset_dir
    def copy_resource_area(cmd_opts)
      web_assets_dir = @paths.dst_resource_dir_abs
      web_assets_dir.mkpath unless web_assets_dir.exist?

      resource_dir = cmd_opts.resource_dir.cleanpath.to_s + "/."

      Giblog.logger&.info "Copy web assets (stylesheets et al) from #{resource_dir} to #{web_assets_dir}"
      FileUtils.cp_r(
        resource_dir,
        web_assets_dir.to_s
      )
    end
  end
end
