module Giblish
  class FindStylePaths
    STYLE_EXTENSIONS = {
      "html5" => ".css",
      "html" => ".css",
      "pdf" => ".yml",
      "web-pdf" => ".css"
    }

    attr_reader :src_style_path, :web_assets_top, :web_dst_css_path

    def initialize(cmd_opts)
      @style_ext = STYLE_EXTENSIONS.fetch(cmd_opts.format, nil)
      raise OptionParser::InvalidArgument, "Unsupported format: #{cmd_opts.format}" if @style_ext.nil?

      # Validate options and resolve all paths
      @web_assets_top = cmd_opts.dstdir / "web_assets"
      @src_style_path = find_style_file(cmd_opts)
      @web_dst_css_path = @web_assets_top / @src_style_path.relative_path_from(@src_style_path.descend.first)
    end

    private

    # returns:: the relative path from the top of the file_tree to
    # the style file
    def find_style_file(cmd_opts)
      r_top = cmd_opts.resource_dir
      file_tree = PathTree.build_from_fs(r_top)

      # Get all files matching the style name
      style_basename = Pathname.new(cmd_opts.style_name).sub_ext(@style_ext)
      style_tree = file_tree.filter(/.*#{style_basename}$/)

      # make sure we have exactly one css file with the given name
      raise OptionParser::InvalidArgument, "Did not find #{style_basename} under #{r_top}" if style_tree.nil?

      if style_tree.leave_pathnames.count > 1
        raise OptionParser::InvalidArgument, "Found #{style_tree.leave_pathnames.count} instances of #{style_basename} under #{r_top}. Requires exactly one."
      end

      style_tree.leave_pathnames[0]
    end
  end

  class FindFontDirs
    FONT_REGEX = /.*\.(ttf)|(TTF)$/

    attr_reader :font_dirs
    def initialize(cmd_opts)
      r_top = cmd_opts.resource_dir
      tree = PathTree.build_from_fs(r_top) do |p|
        FONT_REGEX =~ p.to_s
      end
      @font_dirs = Set.new
      tree&.traverse_preorder do |level, node|
        next unless node.leaf?

        @font_dirs << node.pathname.dirname
      end
    end
  end

  # copy everything under cmd_opts.resource_dir to
  # dst_top/web_assets/.
  class CopyResourcesPreBuild
    attr_reader :css_path

    # required opts:
    # resource_dir:: Pathname to the top of the resource area to be copied
    # style_name:: basename of the css to use for styling
    # dstdir:: Pathname to the destination dir where the copied resources will be
    # stored.
    def initialize(cmd_opts)
      @opts = cmd_opts.dup
      @paths = FindStylePaths.new(cmd_opts)
    end

    def run(src_tree, dst_tree, converter)
      copy_resource_area(@opts)
    end

    private

    # copy everyting under cmd_opts.resource_dir to @web_asset_dir
    def copy_resource_area(cmd_opts)
      web_assets_dir = @paths.web_assets_top
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
