require_relative "config_utils"
require_relative "resourcepaths"
require_relative "docattr_providers"
require_relative "adocsrc_providers"
require_relative "subtreeinfobuilder"
require_relative "docid/docid"
require_relative "search/headingindexer"
require_relative "indexbuilders/depgraphviz"
require_relative "indexbuilders/subtree_indices"

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
        in web_path:
          # do not copy any local resources, use the given web path to link to css
          @docattr_providers << AbsoluteLinkedCss.new(config_opts.web_path)
        else
          4 == 5 # workaround for bug in standardrb formatting
        end

      if config_opts.make_searchable
        # enabling text search
        search_provider = HeadingIndexer.new(config_opts.srcdir)
        @adoc_extensions[:tree_processor] = search_provider
        @post_builders << search_provider
        # TODO: Remove this after testing
        @adoc_extensions[:docinfo_processor] = AddSearchForm
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
    attr_reader :build_options, :doc_attr

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
        *layout_config.docattr_providers,CmdLineDocAttribs.new(config_opts)
      )
      # @doc_attr.add_doc_attr_providers()

      setup_docid(config_opts, @build_options)
      setup_index_generation(config_opts, @build_options, @doc_attr)

      # setup all pre,post, and build options
      @build_options[:adoc_api_opts] = layout_config.adoc_api_opts
      @build_options[:pre_builders] += layout_config.pre_builders
      @build_options[:post_builders] += layout_config.post_builders
      layout_config.adoc_extensions.each do |type, instance|
        @build_options[:adoc_extensions][type] << instance
      end
    end

    # def setup_converter(src_tree, adoc_src_provider)
    #   # compose the attribute provider and associate it with all source
    #   # nodes
    #   data_provider = DataDelegator.new(adoc_src_provider, @doc_attr)
    #   src_tree.traverse_preorder do |level, node|
    #     next unless node.leaf?
    #
    #     node.data = data_provider
    #   end
    #
    #   TreeConverter.new(src_tree, @config_opts.dstdir, @build_options)
    # end

    private

    def setup_index_generation(config_opts, build_options, doc_attr)
      return if config_opts.no_index

      # setup index generation
      idx = SubtreeInfoBuilder.new(doc_attr, nil, SubtreeIndexBase, config_opts.index_basename)
      build_options[:post_builders] << idx
    end

    def setup_docid(config_opts, build_options)
      return unless config_opts.resolve_docid

      # setup docid resolution
      d = DocIdExtension::DocidPreBuilder.new
      build_options[:pre_builders] << d
      docid_pp = DocIdExtension::DocidProcessor.new({id_2_node: d.id_2_node})
      build_options[:adoc_extensions][:preprocessor] << docid_pp

      return if config_opts.no_index

      # generate dep graph if graphviz is available
      dg = DepGraphDot.new(docid_pp.node_2_ids)
      build_options[:post_builders] << dg
    end
  end
end
