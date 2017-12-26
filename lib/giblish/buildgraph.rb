#!/usr/bin/env ruby
#

module Giblish
  # Needed indata
  #
  # - hash of doc-id deps
  # - doc title
  # - relative path from graph to generated doc
  class GraphBuilderGraphviz
    def initialize(processed_docs, paths, options = {})
      @processed_docs = processed_docs
      @paths = paths
      @options = options.dup

      @docid_cache = DocidCollector.docid_cache
      @docid_deps =  DocidCollector.docid_deps
      @dep_graph = build_dep_graph
    end

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
        label_str += "\"#{info.doc_id}\" [label=\"#{info.doc_id} \\n#{info.title}\", URL=\"http://www.svd.se\" target=\"_blank\"]\n"
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
