require_relative "layout_config_result"
require_relative "../docattr_providers"
require_relative "../resourcepaths"
require_relative "../search/headingindexer"

module Giblish
  # AIDEV-NOTE: Builder for HTML layout configuration following established provider pattern
  class HtmlLayoutConfig
    # Builds complete HTML layout configuration.
    #
    # @param resource_paths [ResourcePaths] Resolved paths for resources, styles, and templates
    # @param config_opts [CmdLine::Options] User configuration options
    # @return [LayoutConfigResult] Complete layout configuration with all components
    def self.build(resource_paths, config_opts)
      # AIDEV-NOTE: Create search provider once and reuse in both extensions and post_builders
      search_provider = config_opts.make_searchable ? HeadingIndexer.new(config_opts.srcdir) : nil

      pre_builders = build_pre_builders(resource_paths)
      post_builders = build_post_builders(search_provider)
      adoc_extensions = build_adoc_extensions(search_provider, config_opts)
      docattr_providers = build_docattr_providers(resource_paths, config_opts)

      LayoutConfigResult.new(
        pre_builders: pre_builders,
        post_builders: post_builders,
        adoc_extensions: adoc_extensions,
        adoc_api_opts: {backend: "html"},
        docattr_providers: docattr_providers
      )
    end

    # @param resource_paths [ResourcePaths]
    # @return [Array<CopyResourcesPreBuild>]
    def self.build_pre_builders(resource_paths)
      builders = []
      if resource_paths.src_resource_dir_abs && resource_paths.dst_style_path_rel
        builders << CopyResourcesPreBuild.new(resource_paths)
      end
      builders
    end

    # @param search_provider [HeadingIndexer, nil]
    # @return [Array<HeadingIndexer>]
    def self.build_post_builders(search_provider)
      builders = []
      builders << search_provider if search_provider
      builders
    end

    # @param search_provider [HeadingIndexer, nil]
    # @param config_opts [CmdLine::Options]
    # @return [Hash{Symbol => Array<Object>}]
    def self.build_adoc_extensions(search_provider, config_opts)
      extensions = {}
      if search_provider
        extensions[:tree_processor] = [search_provider]
        extensions[:docinfo_processor] = [AddSearchForm.new(config_opts.search_action_path)]
      end
      extensions
    end

    # @param resource_paths [ResourcePaths]
    # @param config_opts [CmdLine::Options]
    # @return [Array<Object>]
    def self.build_docattr_providers(resource_paths, config_opts)
      providers = []
      if resource_paths.src_resource_dir_abs && resource_paths.dst_style_path_rel
        providers << RelativeCssDocAttr.new(resource_paths.dst_style_path_rel)
      elsif config_opts.server_css
        providers << AbsoluteLinkedCss.new(config_opts.server_css)
      end
      providers
    end

    private_class_method :build_pre_builders, :build_post_builders, :build_adoc_extensions, :build_docattr_providers
  end
end
