require_relative "verbatimtree"

module Giblish
  class SubtreeIndexBase < SubtreeSrcItf
    attr_reader :adoc_source

    def initialize(dst_node, output_basename)
      @output_basename = output_basename
      @adoc_source = <<~DOC_STR
        #{title}
        #{subtitle(dst_node)}
        #{header}

        #{generation_info}

        #{tree(dst_node)}

        #{document_details(dst_node)}

        #{footer}
      DOC_STR
    end

    protected

    def title
      "= Document index"
    end

    def subtitle(dst_node)
      "from #{dst_node.pathname}"
    end

    def header
      ":icons: font"
    end

    def generation_info
      "*Generated by Giblish at:* #{Time.now.strftime("%Y-%m-%d %H:%M")}"
    end

    def tree(dst_node)
      VerbatimTree.new(dst_node, {dir_index_base_name: @output_basename}).source
    end

    def add_depgraph_id
      # include link to dependency graph if it exists
      <<~DEPGRAPH_STR
        _A visual graph of document dependencies can be found
        <<./graph.adoc#,here>>
      DEPGRAPH_STR
    end

    def document_details(dst_node)
      details_str = +"== Document details\n\n"

      dst_node.traverse_preorder do |_level, node|
        next unless node.leaf?

        d = node.data
        details_str << (d.converted ? document_detail(d) : document_detail_fail(d))
      end
      details_str
    end

    def footer
      ""
    end

    # return the adoc string for displaying the source file
    def display_source_file(node_data)
      <<~SRC_FILE_TXT
        Source file::
        #{node_data.src_node.pathname}
      SRC_FILE_TXT
    end

    # return info about any conversion issues during the
    # asciidoctor conversion
    def conversion_issues(node_data)
      return "" if node_data.stderr.empty?

      # extract conversion warnings from asciddoctor std err
      conv_warnings = node_data.stderr.gsub(/^/, " * ")

      # assemble info to index page
      <<~CONV_INFO
        Conversion issues::

        #{conv_warnings}
      CONV_INFO
    end

    def document_detail_fail(node_data)
      <<~FAIL_INFO
        === #{node_data.src_basename}

        #{display_source_file(node_data)}

        Error detail::
        #{node_data.error_msg}

        ''''

      FAIL_INFO
    end

    # Show some details about file content
    def document_detail(node_data)
      <<~DETAIL_SRC
        [[#{Giblish.to_valid_id(node_data.title.encode("utf-8"))}]]
        === #{node_data.title.encode("utf-8")}

        #{"Doc id::\n_#{node_data.docid}_" unless node_data.docid.nil?}

        #{"Purpose::\n#{node_data.purpose_str}" unless node_data.purpose_str.to_s.empty?}

        #{conversion_issues node_data}

        #{display_source_file(node_data)}

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
      return "Could not find history information" unless node_data.respond_to?(:history)

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