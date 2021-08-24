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
  class HeadingIndexer < Asciidoctor::Extensions::Preprocessor
    HEADING_REGEX = /^=+\s+(.*)$/.freeze
    ANCHOR_REGEX = /^\[\[(\w+)\]\]\s*$/.freeze

    def initialize(data_cache)
      super({})
      @data_cache = data_cache
    end

    def process(document, reader)
      # Add doc as a source dependency for doc ids
      src_node = document.attributes["giblish-src-tree-node"]
      puts "headingindexer src_path: #{src_node.pathname}"

      # only index source files that reside on the 'physical' file system
      return if src_node.nil? || !src_node.pathname.exist?

      # make sure we use the correct id elements when indexing
      # sections
      opts = find_id_attributes(reader.lines)
      src_path = src_node.pathname
      
      # Index all headings in the doc
      Giblog.logger.debug { "indexing headings in #{src_path}" }

      @data_cache.add_file_index(
        src_path: src_path,
        # get the title from the raw text (asciidoctor has not yet
        # processed the text)
        title: find_title(reader.lines),
        sections: index_sections(reader, opts)
      )
      # asciidoctor wants the reader object returned
      reader
    end

    private

    # index all section headings found in the current file
    # @return an array of {:id, :title, :line_no} dicts, one for each
    #         indexed heading
    def index_sections(reader, opts)
      sections = []
      line_no = 0
      match_str = ""
      state = :text
      reader.lines.each do |line|
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

    def find_title(lines)
      title = "No title Found!"
      Giblish.process_header_lines(lines) do |line|
        m = /^=+(.*)$/.match(line)
        if m
          # We found a decent title
          title = m[1].strip
        end
      end
      title
    end

    # Find the attributes that determines how section ids are created
    #
    # The section id attributes can come from three different sources,
    # their internal prio is (1 is highest):
    # 1. values in class variable
    # 2. values taken from doc
    # 3. default values
    def find_id_attributes(lines)
      # prio 1 - use values from invoking user
      result = {
        id_prefix: @data_cache.id_prefix,
        id_separator: @data_cache.id_separator
      }
      return result if result[:id_prefix] && result[:id_separator]

      # prio 2
      # use values specified within the doc
      result = find_section_id_attributes(lines, result)

      # prio 3
      # use default values
      result[:id_prefix] = "_" unless result[:id_prefix]
      result[:id_separator] = "_" unless result[:id_separator]
      result
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
end
