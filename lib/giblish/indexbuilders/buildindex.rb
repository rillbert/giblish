# frozen_string_literal: true

require "pathname"
require "git"

require_relative "../pathtree"
require_relative "../gititf"
require_relative "verbatimtree"

module Giblish
  class IndexSrcFromTree
    attr_reader :adoc_source

    # The fixed heading of the table used to display file history
    HISTORY_TABLE_HEADING = <<~HISTORY_HEADER
      File history::
  
      [cols=\"2,3,8\",options=\"header\"]
      |===
      |Date |Author |Message
    HISTORY_HEADER

    def initialize(src_tree)
      @adoc_source = <<~DOC_STR
        #{title}
        #{subtitle(src_tree)}
        #{header}

        #{generation_info}

        #{tree(src_tree)}

        #{document_details(src_tree)}

        #{footer}
      DOC_STR
    end

    protected

    def title
      "= Document index"
    end

    def subtitle(src_tree)
      "from #{src_tree.pathname}"
    end

    def header
      ":icons: font"
    end

    def generation_info
      "*Generated by Giblish at:* #{Time.now.strftime("%Y-%m-%d %H:%M")}"
    end

    def tree(src_tree)
      VerbatimTree.new(src_tree).source
    end

    def add_depgraph_id
      # include link to dependency graph if it exists
      <<~DEPGRAPH_STR
        _A visual graph of document dependencies can be found
        <<./graph.adoc#,here>>
      DEPGRAPH_STR
    end

    def document_details(src_tree)
      details_str = +"== Document details\n\n"

      src_tree.traverse_preorder do |_level, node|
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
    def display_source_file(conv_info)
      <<~SRC_FILE_TXT
        Source file::
        #{conv_info.src_node.pathname}
      SRC_FILE_TXT
    end

    private

    # return info about any conversion issues during the
    # asciidoctor conversion
    def conversion_issues(conv_info)
      return "" if conv_info.stderr.empty?

      # extract conversion warnings from asciddoctor std err
      conv_warnings = conv_info.stderr.gsub(/^/, " * ")

      # assemble info to index page
      <<~CONV_INFO
        Conversion issues::

        #{conv_warnings}
      CONV_INFO
    end

    def history_info(conv_info)
      return "" unless defined?(conv_info.history) && !conv_info.history.empty?

      str = +HISTORY_TABLE_HEADING

      # Generate table rows of history information
      conv_info.history.each do |h|
        str << <<~HISTORY_ROW
          |#{h.date.strftime("%Y-%m-%d")}
          |#{h.author}
          |#{h.message}
  
        HISTORY_ROW
      end
      str << "|===\n\n"
    end

    def document_detail_fail(conv_info)
      <<~FAIL_INFO
        === #{conv_info.src_basename}

        #{display_source_file(conv_info)}

        Error detail::
        #{conv_info.error_msg}

        ''''

      FAIL_INFO
    end

    # Show some details about file content
    def document_detail(conv_info)
      <<~DETAIL_SRC
        [[#{Giblish.to_valid_id(conv_info.title.encode("utf-8"))}]]
        === #{conv_info.title.encode("utf-8")}

        #{"Doc id::\n_#{conv_info.docid}_" unless conv_info.docid.nil?}

        #{"Purpose::\n#{conv_info.purpose_str}" unless conv_info.purpose_str.to_s.empty?}

        #{conversion_issues conv_info}

        #{display_source_file(conv_info)}

        #{history_info(conv_info)}

        '''

      DETAIL_SRC
    end
  end

  class IndexTreeBuilder
    attr_accessor :da_provider

    DEFAULT_BASENAME = "index"

    def initialize(da_provider = nil, api_opt_provider = nil, basename = DEFAULT_BASENAME)
      @da_provider = da_provider
      @api_opt_provider = api_opt_provider
      @basename = basename
      @adoc_source = nil
    end

    def document_attributes(src_node, dst_node, dst_top)
      @da_provider.nil? ? {} : @da_provider.document_attributes(src_node, dst_node, dst_top)
    end

    def api_options(src_node, dst_node, dst_top)
      @api_opt_provider.nil? ? {} : @api_opt_provider.api_options(dst_top)
    end

    def adoc_source(src_node, dst_node, dst_top)
      @adoc_source
    end

    # Called from TreeConverter during post build phase
    #
    # adds a 'index' node for each directory in the source tree
    # and convert that index using the options from the provider
    # objects given at instantiation of this object
    def on_postbuild(src_tree, dst_tree, converter)
      dst_tree.traverse_preorder do |level, dst_node|
        next if dst_node.leaf?

        # get the relative path to the index dir from the top dir
        index_dir = dst_node.pathname.relative_path_from(dst_tree.pathname).cleanpath
        Giblog.logger.info { "Setting up index for #{index_dir}" }

        # build the index source for all nodes below dst_node
        @adoc_source = IndexSrcFromTree.new(dst_node).adoc_source

        # add a virtual 'index.adoc' node as the only node in a source tree
        # with this object as source for conversion options
        # and adoc_source
        v_path = Pathname.new("/virtual") / index_dir / "#{@basename}.adoc"
        v_tree = PathTree.new(v_path, self)
        src_node = v_tree.node(v_path, from_root: true)

        # add the destination node where the converted file will be stored
        i_node = dst_node.add_descendants(@basename)

        # do the conversion
        converter.convert(src_node, i_node, dst_tree)
      end
    end
  end
end
