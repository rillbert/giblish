module Giblish
  # AIDEV-NOTE: Immutable value object holding complete layout configuration
  class LayoutConfigResult
    # @return [Array<Object>] Pre-build phase processors
    attr_reader :pre_builders

    # @return [Array<Object>] Post-build phase processors
    attr_reader :post_builders

    # @return [Hash{Symbol => Array<Object>}] Asciidoctor extensions by type
    attr_reader :adoc_extensions

    # @return [Hash{Symbol => Object}] Options passed to Asciidoctor API
    attr_reader :adoc_api_opts

    # @return [Array<Object>] Document attribute providers
    attr_reader :docattr_providers

    # Creates immutable layout configuration.
    #
    # @param pre_builders [Array<Object>] Objects implementing on_prebuild(src_tree, dst_tree, converter)
    # @param post_builders [Array<Object>] Objects implementing on_postbuild(src_tree, dst_tree, converter)
    # @param adoc_extensions [Hash{Symbol => Array<Object>}] Extension type to array of extension instances
    # @param adoc_api_opts [Hash{Symbol => Object}] Options passed to Asciidoctor API
    # @param docattr_providers [Array<Object>] Objects implementing document_attributes(src_node, dst_node, dst_top)
    def initialize(pre_builders:, post_builders:, adoc_extensions:, adoc_api_opts:, docattr_providers:)
      @pre_builders = pre_builders.freeze
      @post_builders = post_builders.freeze
      @adoc_extensions = adoc_extensions.freeze
      @adoc_api_opts = adoc_api_opts.freeze
      @docattr_providers = docattr_providers.freeze
      freeze
    end
  end
end
