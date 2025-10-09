require_relative "dotdigraphadoc"

module Giblish
  # Provide the source for a graphviz-based index page.
  #
  # Note: The asciidoctor-diagram API seems a bit strange when it comes to storing
  # temporary files:
  # * it uses a document attribute {imagesoutdir} and stores the
  #   generated svg image under that regardless of svg-type.
  # * it uses an option in the diagram macro "cachedir" under which a cached image
  #   is stored.
  class GraphPageBase
    attr_reader :adoc_source

    def initialize(info_2_ids, dst_node, basename, opts = {})
      # use a tmp dir since asciidoctor-diagram generates cache files
      # that it doesn't remove afterwards
      Dir.mktmpdir do |dir|
        # build the graph source
        graph = DotDigraphAdoc.new(
          info_2_ids: info_2_ids,
          opts: {"svg-type" => "inline", "cachedir" => dir}
        )

        @adoc_source = <<~DEPGRAPH_PAGE
          = Dependency graph
          :imagesoutdir: #{dir}

          #{graph.source}

        DEPGRAPH_PAGE
      end
    end
  end

  # Generates a summary page with a docid-based dependency graph for an entire destination
  # tree.
  class DependencyGraphPostBuilder
    # the dependency graph relies on graphwiz (dot), check if we can access that
    def self.dot_supported
      !Giblish.which("dot").nil?
    end

    DEFAULT_BASENAME = "gibgraph"

    # node_2_ids:: a { src_node => [doc id refs]} hash. It will be queried during
    #              the post-build phase => it must be populated before the end of the
    #              build phase
    def initialize(node_2_ids, docattr_provider = nil, api_opt_provider = nil, adoc_src_provider = nil, basename = DEFAULT_BASENAME)
      # this class relies on graphwiz (dot), make sure we can access it
      raise "Could not find the 'dot' tool needed to generate a dependency graph!" unless DependencyGraphPostBuilder.dot_supported

      # require asciidoctor module needed for generating diagrams
      require "asciidoctor-diagram/graphviz"

      @node_2_ids = node_2_ids
      @docattr_provider = docattr_provider
      @api_opt_provider = api_opt_provider
      @adoc_src_provider = adoc_src_provider || GraphPageBase
      @basename = basename

      @adoc_source = nil
    end

    def document_attributes(src_node, dst_node, dst_top)
      @docattr_provider.nil? ? {} : @docattr_provider.document_attributes(src_node, dst_node, dst_top)
    end

    def api_options(src_node, dst_node, dst_top)
      @api_opt_provider.nil? ? {} : @api_opt_provider.api_options(dst_top)
    end

    def adoc_source(src_node, dst_node, dst_top)
      @adoc_source
    end

    # Called from TreeConverter during post build phase
    def on_postbuild(src_tree, dst_tree, converter)
      return unless DependencyGraphPostBuilder.dot_supported

      # convert {src_node => [doc ids]} to {conv_info => [doc ids]}
      info_2_ids = {}
      dst_tree.traverse_preorder do |_level, dst_node|
        next unless dst_node.leaf?

        sn = dst_node.data.src_node
        info_2_ids[dst_node] = @node_2_ids[sn] if @node_2_ids.key?(sn)
      end

      # add a virtual 'gibgraph.adoc' node as the only node in a source tree
      # with this object as provider of both adoc source and conversion options
      v_srcpath = Pathname.new("/virtual") / "#{@basename}.adoc"
      src_node = Gran::PathTree.new(v_srcpath, self).node(v_srcpath, from_root: true)

      # add the destination node where the converted file will be stored
      i_node = dst_tree.add_descendants(@basename)

      # get the adoc source from the provider (Class or instance)
      @adoc_source = if @adoc_src_provider.is_a?(Class)
        @adoc_src_provider.new(info_2_ids, dst_tree, @basename).adoc_source
      else
        @adoc_src_provider.adoc_source
      end

      # do the conversion
      converter.convert(src_node, i_node, dst_tree)
    end
  end
end
