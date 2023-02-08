require "pathname"

module Giblish
  # Provides relevant paths for layout resources based on the given options
  class ResourcePaths
    FORMAT_CONVENTIONS = {
      "html5" => ".css",
      "html" => ".css",
      "pdf" => ".yml",
      "web-pdf" => ".css"
    }

    FONT_REGEX = /.*\.(ttf)|(TTF)$/
    WEB_ASSET_TOP_BASENAME = Pathname.new("web_assets")
    IDX_ERB_TEMPLATE_BASENAME = "idx_template.erb"

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
    attr_reader :dst_webasset_dir_abs

    # the abs path to the top of the source dir for resources
    attr_reader :src_resource_dir_abs

    # the relative path to the erb template for index generation
    attr_reader :idx_erb_template_rel

    # the absolute path to the erb template for index generation
    attr_reader :idx_erb_template_abs

    # attributes:
    #   .format        required
    #   .resource_dir  required
    #   .dst_dir       required
    #   .style_name    optional
    #   .idx_erb_basename    optional
    def initialize(cmd_opts)
      raise InvalidArgument, "Unsupported format: #{cmd_opts.format}" unless FORMAT_CONVENTIONS.key?(cmd_opts.format)

      init_to_default(cmd_opts)

      return if @src_resource_dir_abs.nil?

      # Tweak paths based on the content of a given resource dir
      file_tree = PathTree.build_from_fs(@src_resource_dir_abs)

      @src_style_path_rel = find_style_file(file_tree, cmd_opts.format, cmd_opts.style_name)
      @src_style_path_abs = @src_resource_dir_abs / @src_style_path_rel if @src_style_path_rel
      @dst_style_path_rel = WEB_ASSET_TOP_BASENAME / @src_style_path_rel if @src_style_path_rel

      @font_dirs_abs = find_font_dirs(file_tree)

      erb_template = find_unique_file(file_tree, IDX_ERB_TEMPLATE_BASENAME)
      if erb_template
        @idx_erb_template_rel = erb_template
        @idx_erb_template_abs = @src_resource_dir_abs / @idx_erb_template_rel
      end
    end

    private

    # initialize paths to default values
    def init_to_default(cmd_opts)
      # the top dir for resources
      @src_resource_dir_abs = cmd_opts.resource_dir

      # the destination dir for webassets is always valid for html conversion
      @dst_webasset_dir_abs = cmd_opts.dstdir / WEB_ASSET_TOP_BASENAME if cmd_opts.format.start_with?("html")

      # use the hard-coded default erb template
      @idx_erb_template_rel = Pathname("indexbuilders/#{IDX_ERB_TEMPLATE_BASENAME}")
      @idx_erb_template_abs = Pathname(__dir__) / @idx_erb_template_rel

      @src_style_path_rel = nil
      @src_style_path_abs = nil

      @font_dirs_abs = nil
    end

    # returns:: the relative path from the top of the file_tree to
    # the style file
    def find_style_file(file_tree, format, style_name)
      return nil if style_name.nil?

      # Get all files matching the style name
      style_basename = Pathname.new(style_name).sub_ext(
        FORMAT_CONVENTIONS[format]
      )
      find_unique_file(file_tree, style_basename)
    end

    # returns the (relative) pathname of the file with the given basename or
    # nil if no match was found.
    #
    # Throws if multiple entries exists.
    def find_unique_file(file_tree, basename)
      files = file_tree.match(/.*#{basename}$/)

      if files.nil?
        Giblog.logger.warn { "Did not find #{basename} under #{file_tree.pathname}" }
        return nil
      end

      l = files.leave_pathnames(prune: true)
      if l.count > 1
        raise OptionParser::InvalidArgument, "Found #{l.count} instances of #{style_basename} under #{file_tree.pathname}. Requires exactly one."
      end

      # return the (pruned) path
      l[0]
    end

    # returns:: a Set(Pathname) with all (absolute) directories matching the name criteria
    # for fonts
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
    def initialize(resource_paths)
      @paths = resource_paths
    end

    def on_prebuild(src_tree, dst_tree, converter)
      copy_resource_area
    end

    private

    # copy everyting under cmd_opts.resource_dir to @web_asset_dir
    def copy_resource_area
      web_assets_dir = @paths.dst_webasset_dir_abs
      web_assets_dir.mkpath unless web_assets_dir.exist?

      resource_dir = @paths.src_resource_dir_abs.to_s + "/."

      Giblog.logger&.info "Copy web assets (stylesheets et al) from #{resource_dir} to #{web_assets_dir}"
      FileUtils.cp_r(
        resource_dir,
        web_assets_dir.to_s
      )
    end
  end

  # copy all directories whose name matches a given regex from
  # the source tree to the destination tree.
  class CopyAssetDirsPostBuild
    def initialize(cmd_opts)
      @asset_regex = cmd_opts.copy_asset_folders
      @srcdir = cmd_opts.srcdir
      @dstdir = cmd_opts.dstdir
    end

    # Called from TreeConverter during post build phase
    #
    # copy all directories matching the regexp pattern from the
    # src tree to the dst tree
    def on_postbuild(src_tree, dst_tree, converter)
      return if @asset_regex.nil?

      # build a tree with all dirs matching the given regexp
      st = PathTree.build_from_fs(@srcdir, prune: true) do |p|
        p.directory? && @asset_regex =~ p.to_s
      end

      return if st.nil?

      Giblog.logger&.info "Copy asset directories from #{@srcdir} to #{@dstdir}"
      st.traverse_preorder do |level, node|
        next unless node.leaf?

        n = node.relative_path_from(st)
        src = @srcdir.join(n)
        dst = @dstdir.join(n).dirname
        dst.mkpath

        FileUtils.cp_r(src.to_s, dst.to_s)
      end
    end
  end
end
