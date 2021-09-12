require_relative "dotdigraphadoc"

module Giblish
  # Generates a summary page with a docid-based dependency graph for an entire destination
  # tree.
  class DepGraphDot
    # the dependency graph relies on graphwiz (dot), check if we can access that
    def self.dot_supported
      !Giblish.which("dot").nil?
    end

    # node_2_ids:: a { src_node => [doc id refs]} hash. It will be queried during
    #              the post-build phase => it must be populated before the end of the
    #              build phase
    def initialize(node_2_ids)
      # this class relies on graphwiz (dot), make sure we can access it
      raise "Could not find the 'dot' tool needed to generate a dependency graph!" unless GraphBuilderGraphviz.supported

      # require asciidoctor module needed for generating diagrams
      require "asciidoctor-diagram/graphviz"

      @node_2_ids = node_2_ids
      @adoc_source = ""
    end

    def adoc_source(src_node, dst_node, dst_top)
      @adoc_source
    end

    # Called from TreeConverter during post build phase
    def on_postbuild(src_tree, dst_tree, converter)
      return unless DepGraphDot.dot_supported

      # convert {src_node => [doc ids]} to {conv_info => [doc ids]}
      info_2_ids = {}
      dst_tree.traverse_preorder do |_level, dst_node|
        next unless dst_node.leaf?

        sn = dst_node.data.src_node
        info_2_ids[dst_node] = @node_2_ids[sn] if @node_2_ids.key?(sn)
      end

      # add a virtual 'gibgraph.adoc' node as the only node in a source tree
      # with this object as provider of both adoc source and conversion options
      v_srcpath = Pathname.new("/virtual") / "gibgraph.adoc"
      src_node = PathTree.new(v_srcpath, self).node(v_srcpath, from_root: true)

      # add the destination node where the converted file will be stored
      i_node = dst_tree.add_descendants("gibgraph")

      # use a tmp dir since asciidoctor-diagram generates cache files
      # that it doesn't remove afterwards
      Dir.mktmpdir { |dir|
        # build the graph source
        graph = DotDigraphAdoc.new(
          info_2_ids: info_2_ids,
          opts: {"svg-type" => "inline", "cachedir" => dir}
        )
        @adoc_source = <<~DEPGRAPH_PAGE
          = Dependency graph

          #{graph.source}

        DEPGRAPH_PAGE

        # do the conversion
        converter.convert(src_node, i_node, dst_tree)
        # cleanup(dst_tree)
      }
    end

    private

    def cleanup(dst_tree)
      # remove cache dir and svg image created by asciidoctor-diagram
      # when creating the document dependency graph
      adoc_diag_cache = dst_tree.pathname.join(".asciidoctor")
      FileUtils.remove_dir(adoc_diag_cache) if adoc_diag_cache.directory?

      svg_cache_file = dst_tree.pathname / "docdeps.svg"
      Giblog.logger.info { "Removing cached files at: #{svg_cache_file}" }
      svg_cache_file.delete
    end
  end
end
