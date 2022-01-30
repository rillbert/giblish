# frozen_string_literal: true

module Giblish
  # Generate asciidoc that represents a given pathtree as a
  # verbatim block with indented, clickable entries.
  class VerbatimTree
    # options:
    # dir_index_base_name: String - the basename of the index file
    # residing in each directory
    def initialize(tree, options = {dir_index_base_name: "index"})
      @tree = tree
      @nof_missing_titles = 0
      @options = options.dup
    end

    def source
      # output tree intro
      tree_string = +<<~DOC_HEADER
        [subs=\"normal\"]
        ----
      DOC_HEADER

      # generate each tree entry string
      @tree.traverse_preorder do |level, node|
        next if level == 0

        tree_string << tree_entry_string(level, node)
      end

      # generate the tree footer
      tree_string << "\n----\n"
    end

    private

    def tree_entry_string(level, node)
      # indent 2 * level
      prefix_str = "  " * (level + 1)

      # return only name for directories
      return directory_entry(prefix_str, node) unless node.leaf?

      # return links to content and details for files
      d = node.data
      if d.converted
        tree_entry_converted(prefix_str, node)
      else
        # no converted file exists, show what we know
        "#{prefix_str} FAIL: #{d.src_basename}      <<#{d.src_basename},details>>\n"
      end
    end

    def directory_entry(prefix_str, node)
      p = node.pathname.relative_path_from(@tree.pathname).join(@options[:dir_index_base_name])
      "#{prefix_str} <<#{p}#,#{node.segment}>>\n"
    end

    # Generate an adoc string that will display as
    # DocTitle         (conv issues)  details
    # Where the DocTitle and details are links to the doc itself and a section
    # identified with the doc's title respectively.
    def tree_entry_converted(prefix_str, node)
      # Get the elements of the entry
      doc_title, doc_link, doc_details = format_title_and_ref(node)
      warning_label = node.data.stderr.empty? ? "" : "(conv issues)"

      # Calculate padding to get (conv issues) and details aligned in columns
      padding = 70
      [doc_title, prefix_str, warning_label].each { |p| padding -= p.length }
      padding = 0 unless padding.positive?

      "#{prefix_str} #{doc_link}#{" " * padding}#{warning_label} #{doc_details}"
    end

    # Private: Return adoc elements for displaying a clickable title
    # and a 'details' ref that points to a section that uses the title as an id.
    #
    # Returns [ title, clickableTitleStr, clickableDetailsStr ]
    def format_title_and_ref(node)
      conv_info = node.data

      # Use docid and title in title reference
      title_ref = (conv_info.docid.nil? ? "" : "#{conv_info.docid} - ") + conv_info.title

      # find relative source path from the file to this tree's root
      p = node.pathname.relative_path_from(@tree.pathname).sub_ext(".adoc")

      # remove html markup in the title for displaying in the tree
      stripped_title = title_ref.gsub(/<.*?>/, "")
      [stripped_title, "<<#{p}#,#{stripped_title}>>",
        "<<#{Giblish.to_valid_id(node.pathname.to_s, "_", "_", true)},details>>\n"]
    end
  end
end
