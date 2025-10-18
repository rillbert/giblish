require_relative "../docid/docid"
require_relative "../indexbuilders/depgraphbuilder"

module Giblish
  # AIDEV-NOTE: Immutable value object for DocId configuration
  class DocIdConfig
    # @return [Array<DocIdExtension::DocidPreBuilder>] Pre-build processors
    attr_reader :pre_builders

    # @return [Array<DocIdExtension::DocidProcessor>] Asciidoctor preprocessors
    attr_reader :preprocessors

    # @return [Array<DependencyGraphPostBuilder>] Post-build processors
    attr_reader :post_builders

    # Creates immutable DocId configuration.
    #
    # @param pre_builders [Array<DocIdExtension::DocidPreBuilder>]
    # @param preprocessors [Array<DocIdExtension::DocidProcessor>]
    # @param post_builders [Array<DependencyGraphPostBuilder>]
    def initialize(pre_builders:, preprocessors:, post_builders:)
      @pre_builders = pre_builders.freeze
      @preprocessors = preprocessors.freeze
      @post_builders = post_builders.freeze
      freeze
    end
  end

  # AIDEV-NOTE: Builder for DocId configuration following established provider pattern
  class DocIdConfigBuilder
    # Builds complete DocId configuration based on user options.
    # Returns a null configuration if DocId resolution is disabled.
    #
    # @param config_opts [CmdLine::Options] User configuration with resolve_docid flag
    # @return [DocIdConfig] Configuration with pre-builders, preprocessors, and post-builders
    def self.build(config_opts)
      return null_config unless config_opts.resolve_docid

      docid_prebuilder = DocIdExtension::DocidPreBuilder.new
      docid_processor = DocIdExtension::DocidProcessor.new({id_2_node: docid_prebuilder.id_2_node})

      post_builders = build_post_builders(config_opts, docid_processor)

      DocIdConfig.new(
        pre_builders: [docid_prebuilder],
        preprocessors: [docid_processor],
        post_builders: post_builders
      )
    end

    # @param config_opts [CmdLine::Options]
    # @param docid_processor [DocIdExtension::DocidProcessor]
    # @return [Array<DependencyGraphPostBuilder>]
    def self.build_post_builders(config_opts, docid_processor)
      builders = []

      # Add dependency graph if not disabled and graphviz is available
      unless config_opts.no_index
        if DependencyGraphPostBuilder.dot_supported
          builders << DependencyGraphPostBuilder.new(
            docid_processor.node_2_ids,
            nil,
            nil,
            nil,
            config_opts.graph_basename
          )
        end
      end

      builders
    end

    # @return [DocIdConfig]
    def self.null_config
      DocIdConfig.new(
        pre_builders: [],
        preprocessors: [],
        post_builders: []
      )
    end

    private_class_method :build_post_builders, :null_config
  end
end
