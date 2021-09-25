# frozen_string_literal: true

require "erb"
require "json"
require "pathname"
require "asciidoctor"
require "asciidoctor/extensions"
require_relative "../utils"

module Giblish
  # Implements both an Asciidoctor TreeProcessor hook and a giblish post-build
  # hook.
  #
  # The TreeProcessor hook indexes all headings found in all
  # documents in the tree and copies a 'washed' version of the source lines
  # to a search asset folder in the destination tree.
  #
  # The post build hook copies the completed heading index to the search
  # assets folder.
  #
  # Format of the heading index database:
  # {
  #   fileinfos : [{
  #     filepath : filepath_1,
  #     title : Title,
  #     sections : [{
  #       id : section_id_1,
  #       title : section_title_1,
  #       line_no : line_no
  #     },
  #     {
  #       id : section_id_1,
  #       title : section_title_1,
  #       line_no : line_no
  #     },
  #     ...
  #     ]
  #   },
  #   {
  #     filepath : filepath_2,
  #     ...
  #   }]
  # }
  class HeadingIndexer < Asciidoctor::Extensions::TreeProcessor
    HEADING_REGEX = /^=+\s+(.*)$/.freeze
    ANCHOR_REGEX = /^\[\[(\w+)\]\]\s*$/.freeze
    HEADING_DB_BASENAME = "heading_db.json"
    SEARCH_ASSET_DIRNAME = "gibsearch_assets"

    # src_topdir:: a Pathname to the top dir of the src files
    def initialize(src_topdir)
      super({})

      @src_topdir = src_topdir
      @heading_index = {fileinfos: []}
    end

    # called by Asciidoctor during the conversion of the document.
    def process(document)
      attrs = document.attributes
      src_node = attrs["giblish-info"][:src_node]

      # only index source files that reside on the 'physical' file system
      return if src_node.nil? || !src_node.pathname.exist?

      # make sure we use the correct id elements when indexing
      # sections
      opts = {
        id_prefix: (attrs.key?("idprefix") ? attrs["idprefix"] : "_"),
        id_separator: (attrs.key?("id_separator") ? attrs["id_separator"] : "_")
      }

      # index sections and wash source lines
      # Copy the washed document to the search asset folder
      dst_top = attrs["giblish-info"][:dst_top]
      puts "src_path: #{src_node.pathname}"
      puts "dst_top: #{dst_top.pathname} rel_src: #{rel_src_path(src_node)}"
      write_washed_doc(
        parse_document(document, src_node, opts),
        dst_top.pathname / SEARCH_ASSET_DIRNAME / rel_src_path(src_node)
      )
      nil
    end

    # called by the TreeConverter during the post_build phase
    def on_postbuild(src_topdir, dst_tree, converter)
      search_topdir = dst_tree.pathname / SEARCH_ASSET_DIRNAME

      # store the JSON file
      serialize_section_index(search_topdir, search_topdir)
    end

    private

    # get the relative path from the src_topdirdir to the source node
    #
    # returns:: a Pathname with the relative path
    def rel_src_path(src_node)
      src_node.pathname.relative_path_from(@src_topdir)
    end

    # returns:: the source lines after substituting attributes
    def parse_document(document, src_node, opts)
      Giblog.logger.debug "index headings in #{src_node.pathname} using prefix '#{opts[:id_prefix]}' and separator '#{opts[:id_separator]}'"
      attrs = document.attributes
      doc_info = index_sections(document, opts)

      @heading_index[:fileinfos] << {
        filepath: rel_src_path(src_node),
        title: attrs.key?("doctitle") ? attrs["doctitle"] : "No title found!",
        sections: doc_info[:sections]
      }
      doc_info[:washed_lines]
    end

    # lines:: [lines]
    # dst_path:: Pathname to destination file
    def write_washed_doc(lines, dst_path)
      Giblog.logger.debug { "Copy searchable text to #{dst_path}" }
      dst_path.dirname.mkpath
      File.write(dst_path.to_s, lines.join("\n"))
    end

    # replace {a_doc_attr} with the value of the attribute
    def replace_attrs(attrs, line)
      # find all '{...}' occurrences
      m_arr = line.scan(/\{\w+\}/)
      # replace each found occurence with its doc attr if exists
      m_arr.inject(line) do |memo, match|
        attrs.key?(match[1..-2]) ? memo.gsub(match.to_s, attrs[match[1..-2]]) : memo
      end
    end

    # provide a 'washed' version of all source lines in the document and
    # index all sections.
    #
    # returns:: { washed_lines: [lines], sections: [{:id, :title, :line_no}]}
    def index_sections(document, opts)
      indexed_doc = {
        washed_lines: [],
        sections: []
      }
      sections = indexed_doc[:sections]
      lines = document.reader.source_lines

      line_no = 0
      match_str = ""
      state = :text
      lines.each do |line|
        line_no += 1
        line = replace_attrs(document.attributes, line)
        indexed_doc[:washed_lines] << line

        # implement a state machine that supports both custom
        # anchors for a heading and the default heading ids generated
        # by asciidoctor
        case state
        when :text
          case line
          # detect a heading or an anchor preceeding a heading
          when HEADING_REGEX
            state = :heading
            match_str = Regexp.last_match(1)
          when ANCHOR_REGEX
            state = :expecting_heading
            match_str = Regexp.last_match(1)
          end
        when :expecting_heading
          case line
          when HEADING_REGEX
            # we got a heading, index it
            sections << {
              "id" => match_str,
              "title" => Regexp.last_match(1).strip,
              "line_no" => line_no
            }
          else
            # we did not get a heading, this is ok as well but we can not
            # index it
            Giblog.logger.debug do
              "Did not index the anchor: #{match_str} at "\
              "line #{line_no}, probably not associated with a heading."
            end
          end
          state = :text
        when :heading
          # last line was a heading without an accompanying anchor, index it
          # by creating a new, unique id that matches the one that
          # asciidoctor will assign to this heading when generating html
          sections << {
            "id" => create_unique_id(sections, match_str, opts),
            "title" => Regexp.last_match(1).strip,
            "line_no" => line_no - 1
          }
          state = :text
        end
      end
      indexed_doc
    end

    # find the section id delimiters from the document
    # header, if they are set there
    def find_section_id_attributes(lines, result)
      Giblish.process_header_lines(lines) do |line|
        m = /^:idprefix:(.*)$/.match(line)
        n = /^:idseparator:(.*)$/.match(line)
        result[:id_prefix] = m[1].strip if m && !result[:id_prefix]
        result[:id_separator] = n[1].strip if n && !result[:id_separator]
      end
      result
    end

    # create the anchor id for the given heading in a way that complies
    # with how asciidoctor creates the same id when generating html
    def create_unique_id(sections, heading_str, opts)
      # create the 'default' id the same way as asciidoctor will do it
      id_base = Giblish.to_valid_id(heading_str, opts[:id_prefix], opts[:id_separator])
      return id_base unless sections.find { |s| s["id"] == id_base }

      # handle the case with several sections with the same name by adding
      # a sequence number at the end
      idx = 1
      heading_id = ""
      loop do
        heading_id = "#{id_base}_#{idx += 1}"
        break unless sections.find { |s| s["id"] == heading_id }
      end
      heading_id
    end

    # write the index to a file in dst_dir and remove the base_dir
    # part of the path for each filename
    def serialize_section_index(dst_dir, base_dir)
      dst_dir.mkpath

      heading_db_path = dst_dir.join(HEADING_DB_BASENAME)
      Giblog.logger.info { "writing json to #{heading_db_path}" }

      File.open(heading_db_path.to_s, "w") do |f|
        f.write(@heading_index.to_json)
      end
    end
  end

  class AddSearchForm < Asciidoctor::Extensions::DocinfoProcessor
    use_dsl
    at_location :header

    FORM_DATA = <<~FORM_HTML
      <script type="text/javascript">
      window.onload = function () {
        document.getElementById("calingurl_input").value = window.location.href;
      };
      </script>

      <form class="gibsearch" action="<%=action_path%>">
        <input type="search" name="search-phrase" />
        <input type="checkbox" name="usecase" />
        <input type="checkbox" name="useregexp" />

        <input type="hidden" name="calling-url" id=calingurl_input />
        <input type="hidden" name="search-assets-top-rel" value="<%=sa_top_rel%>"/>
        <input type="hidden" name="css-path" value="<%=css_path%>"/>

        <button type="submit">Search</button>
      </form>
    FORM_HTML

    def process(document)
      attrs = document.attributes
      src_node = attrs["giblish-info"][:src_node]
      dst_node = attrs["giblish-info"][:dst_node]
      dst_top = attrs["giblish-info"][:dst_top]

      to_top_rel = dst_top.relative_path_from(dst_node.parent)
      sa_top_rel = to_top_rel.join("gibsearch_assets").cleanpath
      css_path = ""
      action_path = to_top_rel.join("gibsearch.cgi").cleanpath

      ERB.new(FORM_DATA).result(binding)
    end
  end
end
