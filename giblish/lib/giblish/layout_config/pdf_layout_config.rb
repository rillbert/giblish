require_relative "layout_config_result"
require_relative "../docattr_providers"
require_relative "../utils"

module Giblish
  # AIDEV-NOTE: Combined docattr provider and post-processor for asciidoctor-mathematical
  class PdfMathPostbuilder
    # Cleans up temporary SVG files created by asciidoctor-mathematical.
    #
    # @param src_topdir [Gran::PathTree] Source tree root
    # @param dst_tree [Gran::PathTree] Destination tree
    # @param converter [TreeConverter] Converter instance
    # @return [void]
    def on_postbuild(src_topdir, dst_tree, converter)
      dst_top = src_topdir.pathname
      dst_top.each_child do |c|
        if c.basename.to_s.match?(/^stem-[0-9a-f]*\.svg$/)
          Giblog.logger.debug("will remove #{c}")
          c.delete
        end
      end
    end

    # Provides document attributes for mathematical formula rendering.
    #
    # @param src_node [Gran::PathTree::Node] Source node
    # @param dst_node [Gran::PathTree::Node] Destination node
    # @param dst_top [Pathname] Destination top directory
    # @return [Hash{String => String}] Document attributes
    def document_attributes(src_node, dst_node, dst_top)
      {"mathematical-format" => "svg"}
    end
  end

  # AIDEV-NOTE: Builder for PDF layout configuration following established provider pattern
  class PdfLayoutConfig
    # Builds complete PDF layout configuration.
    #
    # @param resource_paths [ResourcePaths] Resolved paths for resources, styles, and fonts
    # @return [LayoutConfigResult] Complete layout configuration with all components
    def self.build(resource_paths)
      post_builders = build_post_builders
      docattr_providers = build_docattr_providers(resource_paths, post_builders)

      LayoutConfigResult.new(
        pre_builders: [],
        post_builders: post_builders,
        adoc_extensions: {},
        adoc_api_opts: {backend: "pdf"},
        docattr_providers: docattr_providers
      )
    end

    # @return [Array<PdfMathPostbuilder>]
    def self.build_post_builders
      builders = []
      begin
        require "asciidoctor-mathematical"
        builders << PdfMathPostbuilder.new
      rescue LoadError
        Giblog.logger.warn { "Did not find asciidoctor-mathematical. stem blocks will not be rendered correctly!" }
      end
      builders
    end

    # @param resource_paths [ResourcePaths]
    # @param post_builders [Array<PdfMathPostbuilder>]
    # @return [Array<Object>]
    def self.build_docattr_providers(resource_paths, post_builders)
      providers = []

      # Add math postbuilder as provider if it exists
      math_builder = post_builders.find { |b| b.is_a?(PdfMathPostbuilder) }
      providers << math_builder if math_builder

      # Add custom style if configured
      if resource_paths.src_style_path_abs
        providers << PdfCustomStyle.new(
          resource_paths.src_style_path_abs,
          *resource_paths.font_dirs_abs.to_a
        )
      end

      providers
    end

    private_class_method :build_post_builders, :build_docattr_providers
  end
end
