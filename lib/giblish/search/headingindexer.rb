# frozen_string_literal: true

require "json"
require "pathname"
require "asciidoctor"
require "asciidoctor/extensions"
require_relative "../utils"
require_relative "searchdatacache"

# put the indexing in the giblish namespace
module Giblish
  # This hook is called by Asciidoctor once for each document _before_
  # Asciidoctor processes the adoc content.
  #
  # It indexes all headings found in all documents in the tree.
  # The resulting index can be serialized to a JSON file
  # with the following format:
  #
  # {
  #   file_infos : [{
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
  #     filepath : filepath_1,
  #     ...
  #   }]
  # }
  class HeadingIndexer < Asciidoctor::Extensions::TreeProcessor
    HEADING_REGEX = /^=+\s+(.*)$/.freeze
    ANCHOR_REGEX = /^\[\[(\w+)\]\]\s*$/.freeze
    HEADING_DB_BASENAME = "heading_db.json"
    SEARCH_ASSET_DIRNAME = "gibsearch_assets"

    def initialize(src_tree)
      super({})

      @src_tree = src_tree
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
      write_washed_doc(
        parse_document(document, src_node, opts), 
        dst_top.pathname / SEARCH_ASSET_DIRNAME / src_node.relative_path_from(@src_tree)
      )
      nil
    end

    # called by the TreeConverter during the post_build phase
    def on_postbuild(src_tree, dst_tree, converter)
      search_topdir = dst_tree.pathname / SEARCH_ASSET_DIRNAME

      # store the JSON file
      serialize_section_index(search_topdir, search_topdir)
    end

    private

    # returns:: the source lines after substituting attributes
    def parse_document(document, src_node, opts)
      Giblog.logger.debug "index headings in #{src_node.pathname} using prefix '#{opts[:id_prefix]}' and separator '#{opts[:id_separator]}'"
      attrs = document.attributes
      doc_info = index_sections(document, opts)
      
      rel_src_path = src_node.relative_path_from(@src_tree)
      @heading_index[:fileinfos] << {
        filepath: rel_src_path,
        title: attrs.key?("doctitle") ? attrs["doctitle"] : "No title found!",
        sections: doc_info[:sections]
      }
      doc_info[:washed_lines]
    end

    # lines:: [lines]
    # dst_path:: Pathname to destination file
    def write_washed_doc(lines, dst_path)
      Giblog.logger.debug {"Copy searchable text to #{dst_path}"}
      dst_path.dirname.mkpath
      File.write(dst_path.to_s,lines.join('\n'))
    end

    # replace {a_doc_attr} with the value of the attribute
    def replace_attrs(attrs, line)
      # find all '{...}' occurrences
      m_arr = line.scan(/\{\w+\}/)
      # replace each found occurence with its doc attr if exists
      m_arr.inject(line) do |memo, match|
        memo.gsub(match.to_s, attrs[match[1..-2]])
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

  # class TestTreeProc < Asciidoctor::Extensions::TreeProcessor
  #   def process(document)
  #     # pp document.blocks[0].class.instance_methods(false)
  #     attrs = document.attributes
  #     puts "----"
  #     puts "title: #{document.title}"
  #     puts "title old: ", attrs.key?("doctitle") ? attrs["doctitle"] : "No title found!"
  #     puts "Sections: #{document.blocks.collect { |b| b.title }.join(",")}"
  #     # document.blocks.each {|b| puts b.lines }.join("\n--\n")
  #   end
  # end
end
