require_relative "config_utils"
require_relative "docattr_providers"
require_relative "resourcepaths"
require_relative "layout_config/html_layout_config"
require_relative "layout_config/pdf_layout_config"
require_relative "config_builders/docid_config_builder"
require_relative "config_builders/index_config_builder"
require_relative "config_builders/git_index_config_builder"

module Giblish
  # AIDEV-NOTE: Assembles configuration from specialized builders following composition pattern
  class Configurator
    # @return [Hash] Build options for TreeConverter
    attr_reader :build_options

    # @return [DocAttrBuilder] Document attribute builder
    attr_reader :doc_attr

    # @return [Cmdline::Options] User configuration options
    attr_reader :config_opts

    # Creates configuration by assembling layout, DocId, and index configurations.
    #
    # @param config_opts [Cmdline::Options] User configuration options
    def initialize(config_opts)
      @config_opts = config_opts
      @resource_paths = ResourcePaths.new(config_opts)

      # Build layout configuration
      layout_config = build_layout_config(config_opts)

      # Initialize doc attribute builder
      @doc_attr = DocAttrBuilder.new(
        GiblishDefaultDocAttribs.new,
        *layout_config.docattr_providers,
        CmdLineDocAttribs.new(config_opts)
      )

      # Build feature configurations
      docid_config = DocIdConfigBuilder.build(config_opts)
      index_config = build_index_config(config_opts)

      # Assemble final build options
      @build_options = assemble_build_options(layout_config, docid_config, index_config, config_opts)
    end

    private

    # @param config_opts [Cmdline::Options]
    # @return [LayoutConfigResult]
    def build_layout_config(config_opts)
      case config_opts
      in format: "html" then HtmlLayoutConfig.build(@resource_paths, config_opts)
      in format: "pdf" then PdfLayoutConfig.build(@resource_paths)
      else
        raise OptionParser::InvalidArgument, "The given cmd line flags are not supported: #{config_opts.inspect}"
      end
    end

    # @param config_opts [Cmdline::Options]
    # @return [IndexConfig]
    def build_index_config(config_opts)
      IndexConfigBuilder.build(config_opts, @resource_paths, @doc_attr)
    end

    # @param layout_config [LayoutConfigResult]
    # @param docid_config [DocIdConfig]
    # @param index_config [IndexConfig]
    # @param config_opts [Cmdline::Options]
    # @return [Hash]
    def assemble_build_options(layout_config, docid_config, index_config, config_opts)
      # Start with layout configuration
      options = {
        adoc_api_opts: layout_config.adoc_api_opts,
        pre_builders: layout_config.pre_builders.dup,
        post_builders: layout_config.post_builders.dup,
        adoc_extensions: Hash.new { |h, k| h[k] = [] }
      }

      # Merge layout extensions
      layout_config.adoc_extensions.each do |type, instances|
        options[:adoc_extensions][type] += instances
      end

      # Merge docid configuration
      options[:pre_builders] += docid_config.pre_builders
      options[:post_builders] += docid_config.post_builders
      options[:adoc_extensions][:preprocessor] += docid_config.preprocessors

      # Merge index configuration
      options[:post_builders] += index_config.post_builders

      # Add asset copying if configured
      unless config_opts.copy_asset_folders.nil?
        options[:post_builders] << CopyAssetDirsPostBuild.new(config_opts)
      end

      options
    end
  end

  # AIDEV-NOTE: Git-specific configurator using composition instead of inheritance
  class GitRepoConfigurator < Configurator
    # Creates configuration for git repository conversion with history support.
    #
    # @param config_opts [Cmdline::Options] User configuration options
    # @param git_repo_dir [Pathname] Path to git repository root
    def initialize(config_opts, git_repo_dir)
      @git_repo_dir = git_repo_dir
      config_opts.search_action_path ||= "/gibsearch.cgi"
      super(config_opts)
    end

    private

    # @param config_opts [Cmdline::Options]
    # @return [IndexConfig]
    def build_index_config(config_opts)
      GitIndexConfigBuilder.build(config_opts, @resource_paths, @doc_attr, @git_repo_dir)
    end
  end
end
