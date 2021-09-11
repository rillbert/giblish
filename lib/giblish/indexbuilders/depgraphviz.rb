module Giblish

  # Provides a graphviz-formatted di-graph of the provided node<->id ref map.
  # 
  # See https://graphviz.gitlab.io/doc/conv_info/lang.html for one definition of the
  # language.
  class DotGraphAdoc
    # {DocInfo => [doc id refs]}
    # DocInfo:
    # title:: String
    # doc_id:: String
    # dst_rel_path:: String - the relative path from a the repo top to a doc
    #                in the dst tree
    def initialize(info_2_ids)
      # this class relies on graphwiz (dot), make sure we can access that
      raise "Could not find the 'dot' tool needed to generate a dependency graph!" unless GraphBuilderGraphviz.supported

      # require asciidoctor module needed for generating diagrams
      require "asciidoctor-diagram/graphviz"

      @noid_docs = {}
      @next_id = 0
      @info_2_ids = info_2_ids
    end

    def source
      <<~DOC_STR
        #{graph_header}
        #{generate_labels}
        #{generate_deps}
        #{graph_footer}
      DOC_STR
    end

    private

    def graph_header
      <<~DOC_STR
        [graphviz,"docdeps","svg",options="inline"]
        ....
        digraph document_deps {
          bgcolor="#33333310"
          node [shape=note,
                fillcolor="#ebf26680",
                style="filled,solid"
              ]

        rankdir="LR"

      DOC_STR
    end

    def graph_footer
      <<~DOC_STR
        }
        ....
      DOC_STR
    end

    # split title into multiple rows if it is too long
    def format_title(conv_info)
      line_length = 15
      lines = [""]
      unless conv_info&.title.nil?
        conv_info.title.split(" ").inject("") do |l, w|
          line = "#{l} #{w}"
          lines[-1] = line
          if line.length > line_length
            # create a new, empty, line
            lines << ""
            ""
          else
            line
          end
        end
      end
      lines.select { |l| l.length.positive? }.map { |l| l }.join("\n")
    end

    def make_dot_entry(doc_dict, conv_info)
      title = format_title(conv_info)

      # create the label used to display the node in the graph
      dot_entry = if conv_info.docid.nil?
        doc_id = next_fake_id
        @noid_docs[conv_info] = doc_id
        "\"#{doc_id}\"[label=\"-\\n#{title}\""
      else
        doc_id = conv_info.docid
        "\"#{conv_info.docid}\"[label=\"#{conv_info.docid}\\n#{title}\""
      end

      # add clickable links in the case of html output (this is not supported
      # out-of-the-box for pdf).
      rp = conv_info.dst_rel_path
      dot_entry += case rp.extname
                   when ".html"
                     ", URL=\"#{rp}\" ]"
                   else
                     " ]"
      end
      doc_dict[doc_id] = dot_entry
    end

    def generate_labels
      # create an entry in the 'dot' description for each
      # document, sort them according to descending doc id to
      # get them displayed in the opposite order in the graph
      node_dict = {}
      @info_2_ids.each_key do |conv_info|
        make_dot_entry node_dict, conv_info
      end
      # sort the nodes by reverse doc id
      node_dict = node_dict.sort.reverse.to_h

      # produce the string with all node entries
      node_dict.map do |_k, v|
        v
      end.join("\n")
    end

    def generate_deps
      dep_str = ""
      @info_2_ids.each do |conv_info, targets|
        # set either the real or the generated id as source
        src_part = if conv_info.docid.nil?
          "\"#{@noid_docs[conv_info]}\""
        else
          "\"#{conv_info.docid}\""
        end

        if targets.length.zero?
          dep_str += "#{src_part}\n"
          next
        end

        dep_str += "#{src_part} -> {" + targets.reduce("") do |acc, target|
          acc + " \"#{target}\""
        end
        # replace last comma with newline
        dep_str += "}\n"
      end
      dep_str
    end

    def next_fake_id
      @next_id += 1
      "_generated_id_#{@next_id.to_s.rjust(4, "0")}"
    end
  end

  # a post-builder
  class DepGraphDot
    # the dependency graph relies on graphwiz (dot), check if we can access that
    def self.dot_supported
      !Giblish.which("dot").nil?
    end

    # Supported options:
    # :extension - file extension for URL links (default is .html)
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

        Giblog.logger.conv_info { "Setting up graph data..." }
        rel_path = dst_node.relative_path_from(dst_tree)
        src_node = src_tree.parent.node(rel_path)
        result[dst_node.data] = @node_2_id_resolver.ids[src_node]
      end

      # build the graph source
      @adoc_source = DotGraphAdoc.new(result).adoc_source

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
