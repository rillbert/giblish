require_relative "../subtreeinfobuilder"
require_relative "../indexbuilders/subtree_indices"

module Giblish
  # AIDEV-NOTE: Immutable value object for Index configuration
  class IndexConfig
    # @return [Array<SubtreeInfoBuilder>] Post-build processors for index generation
    attr_reader :post_builders

    # Creates immutable Index configuration.
    #
    # @param post_builders [Array<SubtreeInfoBuilder>]
    def initialize(post_builders:)
      @post_builders = post_builders.freeze
      freeze
    end
  end

  # AIDEV-NOTE: Builder for Index configuration following established provider pattern
  class IndexConfigBuilder
    # Builds complete Index configuration with index generation support.
    # Returns a null configuration if index generation is disabled.
    #
    # @param config_opts [Cmdline::Options] User configuration with no_index flag
    # @param resource_paths [ResourcePaths] Resolved paths for templates
    # @param doc_attr [DocAttrBuilder] Document attribute builder
    # @param adoc_src_provider_class [Class] Class for generating index source (defaults to SubtreeIndexBase)
    # @return [IndexConfig] Configuration with index generation post-builders
    def self.build(config_opts, resource_paths, doc_attr, adoc_src_provider_class = SubtreeIndexBase)
      return null_config if config_opts.no_index

      adoc_src_provider = adoc_src_provider_class.new(
        {erb_template_path: resource_paths.idx_erb_template_abs}
      )

      idx = SubtreeInfoBuilder.new(
        doc_attr,
        nil,
        adoc_src_provider,
        config_opts.index_basename
      )

      IndexConfig.new(post_builders: [idx])
    end

    # @return [IndexConfig]
    def self.null_config
      IndexConfig.new(post_builders: [])
    end

    private_class_method :null_config
  end
end
