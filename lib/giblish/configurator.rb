require_relative "config_utils"
require_relative "resourcepaths"
require_relative "docattr_providers"
require_relative "adocsrc_providers"
require_relative "subtreeinfobuilder"
require_relative "docid/docid"
require_relative "search/headingindexer"
require_relative "indexbuilders/depgraphbuilder"
require_relative "indexbuilders/subtree_indices"
require_relative "gitrepos/history_pb"

module Giblish
  class HtmlLayoutConfig
    attr_reader :pre_builders, :post_builders, :adoc_extensions, :adoc_api_opts, :docattr_providers

    def initialize(config_opts)
      @adoc_api_opts = {backend: "html"}
      @pre_builders = []
      @post_builders = []
      @adoc_extensions = {}
      @docattr_providers = []
      case config_opts
        in resource_dir:
          # copy local resources to dst and link the generated html with
          # the given css
          @pre_builders << CopyResourcesPreBuild.new(config_opts)

          # make sure generated html has relative link to the copied css
          @docattr_providers << RelativeCssDocAttr.new(ResourcePaths.new(config_opts).dst_style_path_rel)
        in server_css:
          # do not copy any local resources, use the given web path to link to css
          @docattr_providers << AbsoluteLinkedCss.new(config_opts.server_css)
        else
          4 == 5 # workaround for bug in standardrb formatting
        end

      if config_opts.make_searchable
        # enabling text search
        search_provider = HeadingIndexer.new(config_opts.srcdir)
        @adoc_extensions[:tree_processor] = search_provider
        @post_builders << search_provider

        # add search form to all docs
        @adoc_extensions[:docinfo_processor] = AddSearchForm.new(config_opts.search_action_path)
      end
    end
  end

  class PdfLayoutConfig
    attr_reader :pre_builders, :post_builders, :adoc_extensions, :adoc_api_opts, :docattr_providers

    def initialize(config_opts)
      @adoc_api_opts = {backend: "pdf"}
      @pre_builders = []
      @post_builders = []
      @adoc_extensions = {}
      @docattr_providers = []

      unless config_opts.resource_dir.nil?
        # generate pdf using asciidoctor-pdf with custom styling
        rp = ResourcePaths.new(config_opts)
        @docattr_providers << PdfCustomStyle.new(rp.src_style_path_abs, *rp.font_dirs_abs.to_a)
      end
    end
  end

  # configure all parts needed to execute the options specified by
  # the user
  class Configurator
    attr_reader :build_options, :doc_attr, :config_opts

    # config_opts:: a Cmdline::Options instance with config info
    def initialize(config_opts)
      @config_opts = config_opts
      @build_options = {
        pre_builders: [],
        post_builders: [],
        adoc_api_opts: {},
        # add a hash where all values are initiated as empty arrays
        adoc_extensions: Hash.new { |h, k| h[k] = [] }
      }

      # Initiate the doc attribute repo used during 'run-time'
      @doc_attr = DocAttrBuilder.new(
        GiblishDefaultDocAttribs.new
      )

      layout_config = case config_opts
        in format: "html" then HtmlLayoutConfig.new(config_opts)
        in format: "pdf" then PdfLayoutConfig.new(config_opts)
        else
          raise OptionParser::InvalidArgument, "The given cmd line flags are not supported: #{config_opts.inspect}"
      end

      # setup all options from the chosen layout configuration but
      # override doc attributes with ones from the supplied configuration to
      # ensure they have highest pref
      @doc_attr.add_doc_attr_providers(
        *layout_config.docattr_providers, CmdLineDocAttribs.new(config_opts)
      )

      setup_docid(config_opts, @build_options, @doc_attr)
      setup_index_generation(config_opts, @build_options, @doc_attr)

      # setup all pre,post, and build options
      @build_options[:adoc_api_opts] = layout_config.adoc_api_opts
      @build_options[:pre_builders] += layout_config.pre_builders
      @build_options[:post_builders] += layout_config.post_builders
      layout_config.adoc_extensions.each do |type, instance|
        @build_options[:adoc_extensions][type] << instance
      end

      # add copy of asset dirs if options stipulates this
      @build_options[:post_builders] << CopyAssetDirsPostBuild.new(@config_opts) unless @config_opts.copy_asset_folders.nil?
    end

    protected

    def setup_index_generation(config_opts, build_options, doc_attr)
      return if config_opts.no_index

      # setup index generation
      idx = SubtreeInfoBuilder.new(doc_attr, nil, SubtreeIndexBase, config_opts.index_basename)
      build_options[:post_builders] << idx
    end

    def setup_docid(config_opts, build_options, doc_attr)
      return unless config_opts.resolve_docid

      # setup docid resolution
      d = DocIdExtension::DocidPreBuilder.new
      build_options[:pre_builders] << d
      docid_pp = DocIdExtension::DocidProcessor.new({id_2_node: d.id_2_node})
      build_options[:adoc_extensions][:preprocessor] << docid_pp

      # early exit if user does not want indices
      return if config_opts.no_index

      # generate dep graph if graphviz is available
      dg = DependencyGraphPostBuilder.new(docid_pp.node_2_ids, doc_attr, nil, nil, config_opts.graph_basename)
      build_options[:post_builders] << dg
    end
  end

  # swap standard index generation from the base class to ones including
  # git history.
  class GitRepoConfigurator < Configurator
    def initialize(config_opts, git_repo_dir)
      @git_repo_dir = git_repo_dir
      config_opts.search_action_path ||= "/gibsearch.cgi"
      super(config_opts)
    end

    protected

    def setup_index_generation(config_opts, build_options, doc_attr)
      return if config_opts.no_index

      build_options[:post_builders] << AddHistoryPostBuilder.new(@git_repo_dir)
      build_options[:post_builders] << SubtreeInfoBuilder.new(doc_attr, nil, SubtreeIndexGit, config_opts.index_basename)
    end
  end
end
