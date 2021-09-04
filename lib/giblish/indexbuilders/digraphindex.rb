# frozen_string_literal: true

require_relative "../docinfo"

module Giblish
  # Builds an asciidoc page with an svg image with a
  # digraph showing how documents reference each other.
  #
  # Graphviz is used as the graph generator and must be available
  # as a valid engine via asciidoctor-diagram for this class to work.
  class DigraphIndex
    # the dependency graph relies on graphwiz (dot), check if we can access that
    def self.supported
      !Giblish.which("dot").nil?
    end

    # doc_tree:: a PathTree with absolute src files and the associated
    # DocInfo as data
    # , paths, deployment_info, options = {})
    def initialize(doc_tree)
      # this class relies on graphwiz (dot), make sure we can access that
      raise "Could not find the 'dot' tool needed to generate a dependency graph!" unless GraphBuilderGraphviz.supported

      # require asciidoctor module needed for generating diagrams
      require "asciidoctor-diagram/graphviz"

      @doctree = doc_tree
      # @paths = paths
      # @deployment_info = deployment_info
      @dep_graph = build_dep_graph(@doctree)

      @noid_docs = {}
      @next_id = 0
    end

    # get the asciidoc source for the document.
    def source
      <<~DOC_STR
        #{generate_graph_header}
        #{generate_labels}
        #{generate_deps}
        #{generate_footer}
      DOC_STR
    end

    def cleanup
      # remove cache dir and svg image created by asciidoctor-diagram
      # when creating the document dependency graph
      adoc_diag_cache = @paths.dst_root_abs.join(".asciidoctor")
      FileUtils.remove_dir(adoc_diag_cache) if adoc_diag_cache.directory?
      Giblog.logger.info { "Removing cached files at: #{@paths.dst_root_abs.join("docdeps.svg")}" }
      @paths.dst_root_abs.join("docdeps.svg").delete
    end

    private

    # build a hash with {DocInfo => [doc_id array]}
    def build_dep_graph(src_tree)
      result = {}
      DocidCollector.docid_deps.each do |src_file, id_array|
        d = src_tree.node(src_file)
        raise "Inconsistent docs when building graph!! found no match for #{src_file}" if d.nil?

        result[d] = id_array if d.converted
      end
      result
    end

    def generate_graph_header
      <<~DOC_STR
        [graphviz,"docdeps","svg",options="inline"]
        ....
        digraph notebook {
          bgcolor="#33333310"
          node [shape=note,
                fillcolor="#ebf26680",
                style="filled,solid"
              ]

        rankdir="LR"

      DOC_STR
    end

    def generate_footer
      <<~DOC_STR
        }
        ....
      DOC_STR
    end

    def make_dot_entry(doc_dict, info)
      # split title into multiple rows if it is too long
      line_length = 15
      lines = [""]
      unless info&.title.nil?
        info.title.split(" ").inject("") do |l, w|
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
      title = lines.select { |l| l.length.positive? }.map { |l| l }.join("\n")

      # create the label used to display the node in the graph
      dot_entry = if info.doc_id.nil?
        doc_id = next_fake_id
        @noid_docs[info] = doc_id
        "\"#{doc_id}\"[label=\"-\\n#{title}\""
      else
        doc_id = info.doc_id
        "\"#{info.doc_id}\"[label=\"#{info.doc_id}\\n#{title}\""
      end
      # add clickable links in the case of html output (this is not supported
      # out-of-the-box for pdf).
      rp = info.rel_path.sub_ext(".#{@extension}")
      dot_entry += case @extension
                   when "html"
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
      @dep_graph.each_key do |info|
        make_dot_entry node_dict, info
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
      @dep_graph.each do |info, targets|
        # set either the real or the generated id as source
        src_part = if info.doc_id.nil?
          "\"#{@noid_docs[info]}\""
        else
          "\"#{info.doc_id}\""
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
end
