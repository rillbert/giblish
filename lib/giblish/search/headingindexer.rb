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

    def initialize(data_cache)
      super({})
      @data_cache = data_cache
    end

    def process(document)
      attrs = document.attributes
      # Get the document's source node info (giblish-specific)
      src_node = attrs["giblish-src-tree-node"]

      # only index source files that reside on the 'physical' file system
      return if src_node.nil? || !src_node.pathname.exist?

      # make sure we use the correct id elements when indexing
      # sections
      opts =       {
        id_prefix: (attrs.key?("idprefix") ? attrs["idprefix"] : "_"),
        id_separator: (attrs.key?("id_separator") ? attrs["id_separator"] : "_")
      }

      src_path = src_node.pathname
      Giblog.logger.debug "index headings in #{src_path} using prefix '#{opts[:id_prefix]}' and separator '#{opts[:id_separator]}'"

      # Index all headings in the doc
      @data_cache.add_file_index(
        src_path: src_path,
        title: attrs.key?("doctitle") ? attrs["doctitle"] : "No title found!",
        sections: index_sections(document.reader.source_lines, opts)
      )
      nil
    end

    private

    # index all section headings found in the current file
    # @return an array of {:id, :title, :line_no} dicts, one for each
    #         indexed heading
    def index_sections(lines, opts)
      sections = []
      line_no = 0
      match_str = ""
      state = :text
      lines.each do |line|
        line_no += 1
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
          # we got a heading without an accompanying anchor, index it
          # by creating a new, unique id that matches the one that
          # asciidoctor will assign to this heading when generating html
          sections << {
            "id" => create_unique_id(sections, match_str, opts),
            "title" => Regexp.last_match(1).strip,
            "line_no" => line_no
          }
          state = :text
        end
      end
      sections
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
  end

  class TestAttribs < Asciidoctor::Extensions::TreeProcessor
    def process(document)
      src_node = document.attributes["giblish-src-tree-node"]

      puts "checking idprefix for #{src_node.pathname}..."
      puts "idprefix: #{document.attributes["idprefix"]}" if document.attributes.key?("idprefix")
    end
  end
end
