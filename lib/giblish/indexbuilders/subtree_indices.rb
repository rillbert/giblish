require "erb"
require_relative "verbatimtree"
require_relative "d3treegraph"

module Giblish
  class SubtreeIndexBase < SubtreeSrcItf
    attr_reader :src_location

    DEFAULT_INDEX_ERB = "/standard_index.erb"

    def initialize(pathtree, output_basename)
      @pathtree = pathtree
      @output_basename = output_basename
      @src_location = pathtree.pathname.dirname
      @title = pathtree.segment
    end

    def adoc_source
      erb_template = File.read(__dir__ + DEFAULT_INDEX_ERB)
      ERB.new(erb_template, trim_mode: "<>").result(binding)
    end

    def tree_summary
      VerbatimTree.new(@pathtree.sort_leaf_first!, {dir_index_base_name: @output_basename}).source
      # str = "++++\n"
      # str += D3TreeGraph.new(tree: @pathtree, options: {dir_index_base_name: @output_basename}).source
      # str += "\n++++"
      # str
    end

    def document_details
      details_str = ""

      @pathtree.traverse_preorder do |_level, node|
        next unless node.leaf?

        d = node.data
        details_str << (d.converted ? document_detail(node) : document_detail_fail(d))
      end
      details_str
    end

    protected

    def document_detail_fail(node_data)
      <<~FAIL_INFO
        === #{node_data.src_basename}

        Source file::
        #{node_data.src_node.segment}

        Error detail::
        #{node_data.error_msg}

        ''''

      FAIL_INFO
    end

    # Show some details about file content
    def document_detail(node)
      node_data = node.data
      <<~DETAIL_SRC
        [[#{Giblish.to_valid_id(node.pathname.to_s, "_", "_", true)}]]
        === pass:[#{node_data.title.encode("utf-8")}]

        #{"Doc id::\n_#{node_data.docid}_" unless node_data.docid.nil?}

        #{"Purpose::\n#{node_data.purpose_str}" unless node_data.purpose_str.to_s.empty?}

        #{if node_data.stderr.empty?
            ""
          else
            "Conversion issues::\n"\
            "#{node_data.stderr.gsub(/^/, " * ")}"
          end
        }

        Source file::
        #{node_data.src_node.segment}

        '''

      DETAIL_SRC
    end
  end

  # Generates a directory index with history info for all files under the
  # given subdir node.
  class SubtreeIndexGit < SubtreeIndexBase
    # The fixed heading of the table used to display file history
    HISTORY_TABLE_HEADING = <<~HISTORY_HEADER
      File history::
  
      [cols=\"2,3,8,3\",options=\"header\"]
      |===
      |Date |Author |Message |Sha1
    HISTORY_HEADER

    HISTORY_TABLE_FOOTING = <<~HIST_FOOTER
      
      |===\n\n
    HIST_FOOTER

    def subtitle(dst_node)
      "from #{dst_node.data.branch}"
    end

    def document_detail_fail(node_data)
      super(node_data) + generate_history_info(node_data)
    end

    def document_detail(node_data)
      super(node_data) + generate_history_info(node_data)
    end

    def generate_history_info(node_data)
      return "Could not find history information\n\n" unless node_data.respond_to?(:history)

      # Generate table rows of history information
      rows = node_data.history.collect do |h|
        <<~HISTORY_ROW
          |#{h.date.strftime("%Y-%m-%d")}
          |#{h.author}
          |#{h.message}  
          |#{h.sha1[0..7]} ... 
        HISTORY_ROW
      end.join("\n\n")
      HISTORY_TABLE_HEADING + rows + HISTORY_TABLE_FOOTING
    end
  end
end
