require_relative "../pathtree"

module Giblish
  module DocIdExtension
    @docid_refs = {}
    class << self
      attr_accessor :docid_cache, :docid_refs
    end

    # Build a hash of {docid => src_node} that can be used to resolve
    # doc id references to valid dst paths
    class DocIdCacheBuilder
      attr_accessor :cache

      # The minimum number of characters required for a valid doc id
      ID_MIN_LENGTH = 2

      # The maximum number of characters required for a valid doc id
      ID_MAX_LENGTH = 10

      # the regex used to find :docid: entries in the doc header
      DOCID_REGEX = /^:docid: +(.*)$/.freeze

      def initialize
        @cache = {}
      end

      # find a :docid: entry in the document header and cache it
      def run(tree_node)
        return unless tree_node.leaf?

        parse_node(tree_node)
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
          if doc_id_ok?(id)
            @cache[id] = node
          else
            Giblog.logger.error { "Invalid docid: #{id} in file #{path}, this will be ignored!" }
          end
        end
      end

      # make sure the id is within the designated length and
      # does not contain a '#' symbol
      def doc_id_ok?(doc_id)
        if @cache.key? doc_id
          Giblog.logger.warn { "Found same doc id twice: (#{doc_id}). Associates this id with #{pathname} and _not_ to file #{@docid_cache[id]}." }
        end
        (doc_id.length.between?(ID_MIN_LENGTH, ID_MAX_LENGTH) && !doc_id.include?("#"))
      end
    end

    # A preprocessor extension to the Asciidoctor engine that transforms all
    # <<:docid:>> references found in the adoc source into the matching
    # file reference.
    # It is dependent on that its 'docid_cache' has been filled before it is
    # invoked via Asciidoctor.
    class DocidResolver < Asciidoctor::Extensions::Preprocessor
      @docid_refs = {}
      class << self
        attr_accessor :docid_refs
      end

      def initialize(opts)
        super(opts)
        @docid_cache = opts[:docid_cache].cache
      end

      # The regex that matches docid references in files
      DOCID_REF_REGEX = /<<\s*:docid:\s*(.*?)>>/.freeze

      # This hook is called by Asciidoctor once for each document _before_
      # Asciidoctor processes the adoc content.
      #
      # It replaces references of the format <<:docid: ID-1234,Hello >> with
      # references to a resolved relative path.
      def process(document, reader)
        # Add doc as a source dependency for doc ids
        src_node = document.attributes["giblish-src-tree-node"]

        # add this file as a source for dependencies
        docid_refs[src_node] ||= []

        # Convert all docid refs to valid relative refs
        reader.lines.each do |line|
          docid_refs[src_node] += parse_line(line, src_node)
        end

        # we only care for one ref to a specific target, remove duplicates
        docid_refs[src_node] = docid_refs[src_node].uniq

        # the asciidoctor engine wants the reader back
        reader
      end

      private

      def docid_refs
        self.class.docid_refs
      end

      # parse one line for valid docid references
      def parse_line(line, src_node)
        refs = []
        line.gsub!(DOCID_REF_REGEX) do |_m|
          # parse the ref
          target_id, section, display_str = parse_doc_id_ref(Regexp.last_match(1))
          Giblog.logger.debug { "Found docid ref to #{target_id} in file: #{src_node.pathname}..." }

          # make sure it exists in the cache
          unless @docid_cache.key?(target_id)
            Giblog.logger.warn { "Could no resolve ref to #{target_id} from file: #{src_node.pathname}..." }
            break "<<UNKNOWN_DOC, Could not resolve doc id reference !!!>>"
          end

          # add the referenced doc id as a target dependency of this document
          refs << target_id

          # get the relative path from this file to the target file
          target_node = @docid_cache[target_id]
          rel_path = target_node.pathname.relative_path_from(src_node.pathname.dirname)

          # return the resolved reference
          "<<#{rel_path}##{section}#{display_str}>>"
          # transform_ref(target_id, section, display_str, src_path)
        end
        refs
      end

      # Get the relative path from the src doc to the
      # doc with the given doc id
      # def get_rel_path(src_path, doc_id)
      #   raise ArgumentError("unknown doc id: #{doc_id}") unless docid_cache.key? doc_id

      #   rel_path = docid_cache[doc_id]
      #     .dirname
      #     .relative_path_from(Pathname.new(src_path).dirname) +
      #     docid_cache[doc_id].basename
      #   rel_path.to_s
      # end

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

      # Transform a :doc_id: reference to its resolved relative path
      #
      # The result is a valid ref in the form
      # <<target_doc.adoc#[section][,display_str]>>
      # def transform_ref(target_id, section, display_str, rel_path)
      #   # resolve the doc id ref to a valid relative path
      #   # rel_path = get_rel_path(src_path, target_id)
      #   # return the transformed ref
      #   "<<#{rel_path}##{section}#{display_str}>>"
      # end
    end
  end
end
