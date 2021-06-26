require_relative "../pathtree"

module Giblish
  # Build a hash of {docid => src_node} that can be used to resolve
  # doc id references to valid dst paths
  class DocIdPreprocessor
    attr_reader :docid_cache

    # The minimum number of characters required for a valid doc id
    ID_MIN_LENGTH = 2

    # The maximum number of characters required for a valid doc id
    ID_MAX_LENGTH = 10

    # @param docid_cache   an array where each found docid is cached
    # @param file_set      the set of paths
    def initialize(opts: {})
      @opts = opts
      @docid_cache = {}
    end

    # find a :docid: entry in the document header and cache it
    def run(tree_node)
      return unless tree_node.leaf?

      parse_node(tree_node)
    end

    private

    DOCID_REGEX = /^:docid: +(.*)$/.freeze

    # Check if a :docid: <id> entry exists in the header.
    # According to http://www.methods.co.nz/asciidoc/userguide.html#X95
    # the header is optional, but if it exists it:
    # - must start with a titel (=+ <My Title>)
    # - ends with one or more blank lines
    # - does not contain any blank line
    #
    def parse_node(node)
      p = node.pathname
      Giblog.logger.debug { "parsing file #{p} for docid..." }
      Giblish.process_header_lines_from_file(p) do |line|
        next unless DOCID_REGEX.match(line)

        # There is a docid defined, cache the path and doc id
        id = Regexp.last_match(1).strip
        Giblog.logger.debug { "found possible docid: #{id}" }
        if doc_id_ok?(id)
          @docid_cache[id] = node
        else
          Giblog.logger.error { "Invalid docid: #{id} in file #{path}, this will be ignored!" }
        end
      end
    end

    # make sure the id is within the designated length and
    # does not contain a '#' symbol
    def doc_id_ok?(doc_id)
      if @docid_cache.key? doc_id
        Giblog.logger.warn { "Found same doc id twice: (#{doc_id}). Associates this id with #{pathname} and _not_ to file #{@docid_cache[id]}." }
      end
      (doc_id.length.between?(ID_MIN_LENGTH, ID_MAX_LENGTH) && !doc_id.include?("#"))
    end
  end
end
