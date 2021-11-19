require "asciidoctor"
require_relative "../pathtree"

module Giblish
  module DocIdExtension
    # Build a hash of {docid => src_node} that can be used to resolve
    # doc id references to valid dst paths
    class DocidPreBuilder
      attr_accessor :id_2_node

      # The minimum number of characters required for a valid doc id
      ID_MIN_LENGTH = 2

      # The maximum number of characters required for a valid doc id
      ID_MAX_LENGTH = 10

      # the regex used to find :docid: entries in the doc header
      DOCID_REGEX = /^:docid: +(.*)$/.freeze

      def initialize
        @id_2_node = {}
      end

      # called during the pre-build phase
      def on_prebuild(src_tree, dst_tree, converter)
        src_tree.traverse_preorder do |level, src_node|
          next unless src_node.leaf?

          parse_node(src_node)
        end
      end

      private

      # Check if a :docid: <id> entry exists in the header of the doc
      # denoted by 'node'.
      # According to http://www.methods.co.nz/asciidoc/userguide.html#X95
      # the header is optional, but if it exists it:
      # - must start with a titel (=+ <My Title>)
      # - ends with one or more blank lines
      # - does not contain any blank line
      def parse_node(node)
        p = node.pathname
        Giblog.logger.debug { "parsing file #{p} for docid..." }
        Giblish.process_header_lines_from_file(p) do |line|
          next unless DOCID_REGEX.match(line)

          # There is a docid defined, cache the path and doc id
          id = Regexp.last_match(1).strip
          Giblog.logger.debug { "found possible docid: #{id}" }
          if doc_id_ok?(id, p)
            @id_2_node[id] = node
          else
            Giblog.logger.error { "Invalid docid: #{id} in file #{p}, this will be ignored!" }
          end
        end
      end

      # make sure the id is within the designated length and
      # does not contain a '#' symbol
      def doc_id_ok?(doc_id, path)
        if @id_2_node.key? doc_id
          Giblog.logger.warn { "Found same doc id twice: (#{doc_id}). This id will be associated with '#{path}' and _not_ with '#{@id_2_node[id]}'." }
        end
        (doc_id.length.between?(ID_MIN_LENGTH, ID_MAX_LENGTH) && !doc_id.include?("#"))
      end
    end

    # A preprocessor extension to the Asciidoctor engine that transforms all
    # <<:docid:>> references found in the adoc source into the matching
    # file reference.
    #
    # It requiers a populated 'id_2_node' with {docid => src_node} before
    # the first invokation of the 'process' method via Asciidoctor.
    #
    # When running, it builds a publicly available 'node_2_ids' map.
    class DocidProcessor < Asciidoctor::Extensions::Preprocessor
      # {src_node => [referenced doc_id's]}
      attr_reader :node_2_ids

      # required options:
      #
      # id_2_node:: {docid => src_node }
      def initialize(opts)
        raise ArgumentError, "Missing required option: :id_2_node!" unless opts.key?(:id_2_node)

        super(opts)
        @id_2_node = opts[:id_2_node]

        # init new keys in the hash with an empty array
        @node_2_ids = Hash.new { |h, k| h[k] = [] }
      end

      # The regex that matches docid references in files
      DOCID_REF_REGEX = /<<\s*:docid:\s*(.*?)>>/.freeze
      PASS_MACRO_REGEX = /pass:\[.*\]/

      # This hook is called by Asciidoctor once for each document _before_
      # Asciidoctor processes the adoc content.
      #
      # It replaces references of the format <<:docid: ID-1234,Hello >> with
      # references to a resolved relative path.
      def process(document, reader)
        # Add doc as a source dependency for doc ids
        gib_data = document.attributes["giblish-info"]
        if gib_data.nil?
          Giblog.logger.error "The docid preprocessor did not find required info in the doc attribute. (Doc title: #{document.title}"
          return reader
        end

        src_node = gib_data[:src_node]

        # Convert all docid refs to valid relative refs
        reader.lines.each do |line|
          # remove commented lines
          next if line.start_with?("//")

          @node_2_ids[src_node] += parse_line(line, src_node)
        end

        # we only care for one ref to a specific target, remove duplicates
        @node_2_ids[src_node] = @node_2_ids[src_node].uniq

        # the asciidoctor engine wants the reader back
        reader
      end

      private

      # substitutes docid references with the corresponding relative path
      # references.
      #
      # returns:: Array of found docid references
      def parse_line(line, src_node)
        refs = []
        # remove all content within a 'pass:[]' macro from the parser
        line.gsub!(PASS_MACRO_REGEX)

        line.gsub!(DOCID_REF_REGEX) do |_m|
          # parse the ref
          target_id, section, display_str = parse_doc_id_ref(Regexp.last_match(1))
          Giblog.logger.debug { "Found docid ref to #{target_id} in file: #{src_node.pathname}..." }

          # make sure it exists in the cache
          unless @id_2_node.key?(target_id)
            Giblog.logger.warn { "Could not resolve ref to #{target_id} from file: #{src_node.pathname}..." }
            break "<<UNKNOWN_DOC, Could not resolve doc id reference !!!>>"
          end

          # add the referenced doc id as a target dependency of this document
          refs << target_id

          # get the relative path from this file to the target file
          target_node = @id_2_node[target_id]
          rel_path = target_node.pathname.relative_path_from(src_node.pathname.dirname)

          # return the resolved reference
          "<<#{rel_path}##{section}#{display_str}>>"
        end
        refs
      end

      # input_str shall be the expression between
      # <<:docid:<input_str>>> where the <input_str> is in the form
      # <id>[#section][,display_str]
      #
      # returns an array with [id, section, display_str]
      def parse_doc_id_ref(input_str)
        ref, display_str = input_str.split(",").each(&:strip)
        id, section = ref.split "#"

        display_str = id.dup if display_str.nil?
        display_str.prepend ","

        section = "" if section.nil?

        [id, section, display_str]
      end
    end
  end
end
