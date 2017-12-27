#!/usr/bin/env ruby
#

module Giblish
  # Builds an asciidoc page with an svg image with a
  # digraph showing how documents reference each other.
  #
  # Graphviz is used as the graph generator and must be available
  # as a valid engine via asciidoctor-diagram for this class to work.
  class GraphBuilderGraphviz
    # Supported options:
    # :extension - file extension for URL links (default is .html)
    def initialize(processed_docs, paths, options = {})
      @processed_docs = processed_docs
      @paths = paths
      @options = options.dup
      @extension = options.key?(:extension) ? options.key?[:extension] : ".html"
      @docid_cache = DocidCollector.docid_cache
      @docid_deps =  DocidCollector.docid_deps
      @dep_graph = build_dep_graph
    end

    # get the asciidoc source for the document.
    def source
      <<~DOC_STR
        #{generate_header}
        #{generate_labels}
        #{generate_deps}
        #{generate_footer}
      DOC_STR
    end

    private

    def build_dep_graph
      result = {}
      @docid_deps.each do |src_file, id_array|
        d = @processed_docs.find do |doc|
          doc.src_file.to_s.eql? src_file
        end
        raise "Inconsistent docs when building graph!! found no match for #{src_file}" if d.nil?
        result[d] = id_array
      end
      result
    end

    def generate_header
      <<~DOC_STR
        = Document dependencies

        [graphviz,"docdeps","svg",options="inline"]
        ....
        digraph notebook {
      DOC_STR
    end

    def generate_footer
      <<~DOC_STR
        }
        ....
      DOC_STR
    end

    def generate_labels
      label_str = ""
      @dep_graph.each_key do |info|
        rp = info.rel_path.sub_ext(@extension)
        label_str += "\"#{info.doc_id}\" [label=\"#{info.doc_id} \\n#{info.title}\", URL=\"#{rp}\" target=\"_blank\"]\n"
      end
      label_str
    end

    def generate_deps
      dep_str = ""
      @dep_graph.each do |info, targets|
        src_part = "\"#{info.doc_id}\""
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
  end
end
