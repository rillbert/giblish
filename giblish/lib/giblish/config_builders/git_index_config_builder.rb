require_relative "index_config_builder"
require_relative "../gitrepos/history_pb"
require_relative "../indexbuilders/subtree_indices"

module Giblish
  # AIDEV-NOTE: Builder for git-specific Index configuration with history support
  class GitIndexConfigBuilder
    # Builds complete Index configuration with git history support.
    # Returns a null configuration if index generation is disabled.
    #
    # @param config_opts [Cmdline::Options] User configuration with no_index flag
    # @param resource_paths [ResourcePaths] Resolved paths for templates
    # @param doc_attr [DocAttrBuilder] Document attribute builder
    # @param git_repo_dir [Pathname] Path to git repository root
    # @return [IndexConfig] Configuration with index generation and git history support
    def self.build(config_opts, resource_paths, doc_attr, git_repo_dir)
      return IndexConfigBuilder.null_config if config_opts.no_index

      post_builders = []
      post_builders << AddHistoryPostBuilder.new(git_repo_dir)

      adoc_src_provider = SubtreeIndexGit.new(
        {erb_template_path: resource_paths.idx_erb_template_abs}
      )

      idx = SubtreeInfoBuilder.new(
        doc_attr,
        nil,
        adoc_src_provider,
        config_opts.index_basename
      )
      post_builders << idx

      IndexConfig.new(post_builders: post_builders)
    end
  end
end
