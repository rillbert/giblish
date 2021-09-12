module Giblish

  # Generates a summary page with a docid-based dependency graph for an entire destination
  # tree.
  class DepGraphDot
    # the dependency graph relies on graphwiz (dot), check if we can access that
    def self.dot_supported
      !Giblish.which("dot").nil?
    end

    # node_2_id_resolver:: an object responding to the 'node_2_ids' method. This method is called
    #                      during the post-build execution of this class.
    def initialize(node_2_id_resolver)
      # this class relies on graphwiz (dot), make sure we can access that
      raise "Could not find the 'dot' tool needed to generate a dependency graph!" unless GraphBuilderGraphviz.supported

      # require asciidoctor module needed for generating diagrams
      require "asciidoctor-diagram/graphviz"

      @node_2_id_resolver = node_2_id_resolver
    end

    # Called from TreeConverter during post build phase
    def run(src_tree, dst_tree, converter)
      return unless dot_supported

      result = {}
      # build graph data {DocInfo => doc id refs}
      dst_tree.traverse_preorder do |level, dst_node|
        next if dst_node.leaf?

        node_2_id_map = @node_2_id_resolver.node_2_ids

        Giblog.logger.conv_info { "Setting up graph data..." }
        rel_path = dst_node.relative_path_from(dst_tree)
        src_node = src_tree.parent.node(rel_path)
        result[dst_node.data] = @node_2_id_resolver.ids[src_node]
      end

      # build the graph source
      @adoc_source = DotDigraphAdoc.new(result).adoc_source

      # add a virtual 'index.adoc' node as the only node in a source tree
      # with this object as source for conversion options
      # and adoc_source
      v_path = Pathname.new("/virtual") / "gibgraph.adoc"
      v_tree = PathTree.new(v_path, self)
      src_node = v_tree.node(v_path, from_root: true)

      # add the destination node where the converted file will be stored
      i_node = dst_tree.add_descendants("gibgraph")

      # do the conversion
      converter.convert(src_node, i_node, dst_tree)

      cleanup(dst_tree)
    end

    private

    def cleanup(dst_tree)
      # remove cache dir and svg image created by asciidoctor-diagram
      # when creating the document dependency graph
      adoc_diag_cache = dst_tree.pathname.join(".asciidoctor")
      FileUtils.remove_dir(adoc_diag_cache) if adoc_diag_cache.directory?
      Giblog.logger.conv_info { "Removing cached files at: #{@paths.dst_root_abs.join("docdeps.svg")}" }
      dst_tree.join("docdeps.svg").delete
    end

    # build a hash with {DocInfo => [doc_id array]}
    # def build_graph_data(node_2_ids)
    #   result = {}
    #   node_2_ids.each do |src_file, id_array|
    #     d = @processed_docs.find do |doc|
    #       doc.src_basename.to_s.eql? src_file
    #     end
    #     raise "Inconsistent docs when building graph!! found no match for #{src_file}" if d.nil?

    #     result[d] = id_array if d.converted
    #   end
    #   result
    # end
  end
end
