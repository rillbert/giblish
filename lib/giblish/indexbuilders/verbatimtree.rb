# frozen_string_literal: true

module Giblish
  # Generate asciidoc that represents a given pathtree as a
  # verbatim block with indented, clickable entries.
  class VerbatimTree
    # options:
    # dir_index_base_name: String - the basename of the index file
    # residing in each directory
    def initialize(tree, options)
      @tree = tree
      @nof_missing_titles = 0
      @options = options.dup
    end

    def source
      # output tree intro
      tree_string = String.new(
        <<~DOC_HEADER
          [subs=\"normal\"]
          ----
        DOC_HEADER
      )

      # generate each tree entry string
      @tree.traverse_top_down do |level, node|
        tree_string << tree_entry_string(level, node)
      end

      # generate the tree footer
      tree_string << "\n----\n"
    end

    private

    # Private: Return adoc elements for displaying a clickable title
    # and a 'details' ref that points to a section that uses the title as an id.
    #
    # Returns [ title, clickableTitleStr, clickableDetailsStr ]
    def format_title_and_ref(doc_info)
      doc_info.title = "NO TITLE FOUND (#{@nof_missing_titles += 1}) !" unless doc_info.title

      # Manipulate the doc title if we have a doc id
      title = String.new
      title << "#{doc_info.doc_id} - " unless doc_info.doc_id.nil?
      title << doc_info.title

      [title, "<<#{doc_info.rel_path}#,#{title}>>",
        "<<#{Giblish.to_valid_id(doc_info.title)},details>>\n"]
    end

    # Generate an adoc string that will display as
    # DocTitle         (conv issues)  details
    # Where the DocTitle and details are links to the doc itself and a section
    # identified with the doc's title respectively.
    def tree_entry_converted(prefix_str, doc_info)
      # Get the elements of the entry
      doc_title, doc_link, doc_details = format_title_and_ref doc_info
      warning_label = doc_info.stderr.empty? ? "" : "(conv issues)"

      # Calculate padding to get (conv issues) and details aligned between entries
      padding = 70
      [doc_title, prefix_str, warning_label].each { |p| padding -= p.length }
      padding = 0 unless padding.positive?
      "#{prefix_str} #{doc_link}#{" " * padding}#{warning_label} #{doc_details}"
    end

    def directory_entry(prefix_str, node)
      p = node.pathname.relative_path_from(@tree.pathname).join(@options[:dir_index_base_name])
      "#{prefix_str} <<#{p}#,#{node.name}>>\n"
    end

    def tree_entry_string(level, node)
      # indent 2 * level
      prefix_str = "  " * (level + 1)

      # return only name for directories
      return directory_entry(prefix_str, node) unless node.leaf?

      # return links to content and details for files
      # node.data is a DocInfo instance
      d = node.data
      if d.converted
        tree_entry_converted prefix_str, d
      else
        # no converted file exists, show what we know
        "#{prefix_str} FAIL: #{d.src_file}      <<#{d.src_file},details>>\n"
      end
    end
  end

  class SearchBoxGenerator
    def initialize(converter, deployment_info)
      @converter = converter
      @search_opts = {
        web_assets_top: deployment_info.web_path,
        search_assets_top: deployment_info.search_assets_path
      }
    end

    def source
      Giblish.generate_search_box_html(
        @converter.converter_options[:attributes]["stylesheet"],
        "/cgi-bin/giblish-search.cgi",
        @search_opts
      )
    end
  end

  class DocIdIndexInfo
    def initialize(processed_docs)
      @processed_docs = processed_docs
    end

    def source
      duplicates = duplicate_docids
      dup_str = "WARNING: The following document ids are used for more than one document: "\
                "_#{duplicates.map(&:to_s).join(",")}_"

      <<~DOC_ID_INFO
        *Document id numbers:* The 'largest' document id found when resolving
        :docid: tags in all documents is *#{largest_docid}*.

        #{dup_str unless duplicates.length.zero?}

      DOC_ID_INFO
    end

    private

    # return the (lexically) largest doc_id found
    def largest_docid
      @processed_docs.max_by(&:doc_id).doc_id
    end

    # find the duplicate doc ids (if any)
    def duplicate_docids
      docs = @processed_docs.select { |doc| @processed_docs.count { |d2| d2.doc_id == doc.doc_id } > 1 }
      docs.map(&:doc_id).sort.uniq
    end
  end
end
