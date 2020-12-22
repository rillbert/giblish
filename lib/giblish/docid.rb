# frozen_string_literal: true

require_relative "./utils"
require "asciidoctor"
require "asciidoctor/extensions"

# put docid stuff in the giblish namespace
module Giblish
  # Collects all :docid: entries in the given file set and caches them
  # in the given cache.
  class DocidPass1
    # The minimum number of characters required for a valid doc id
    ID_MIN_LENGTH = 2

    # The maximum number of characters required for a valid doc id
    ID_MAX_LENGTH = 10

    # @param docid_cache   an array where each found docid is cached
    # @param file_set      the set of paths
    def initialize(docid_cache:, adoc_files:)
      @docid_cache = docid_cache
      @adoc_files = adoc_files
    end

    # find all :docid: entries and cache a Pathname
    def run
      @adoc_files.each { |p| parse_file(p) }
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
    # rubocop:disable Metrics/MethodLength
    def parse_file(path)
      Giblog.logger.debug { "parsing file #{path} for docid..." }
      Giblish.process_header_lines_from_file(path) do |line|
        next unless DOCID_REGEX.match(line)

        # There is a docid defined, cache the path and doc id
        id = Regexp.last_match(1).strip
        Giblog.logger.debug { "found possible docid: #{id}" }
        if doc_id_ok?(id)
          add_docid(id, path)
        else
          Giblog.logger.error { "Invalid docid: #{id} in file #{path}, this will be ignored!" }
        end
      end
    end
    # rubocop:enable Metrics/MethodLength

    # make sure the id is within the designated length and
    # does not contain a '#' symbol
    def doc_id_ok?(doc_id)
      (doc_id.length.between?(ID_MIN_LENGTH, ID_MAX_LENGTH) &&
        !doc_id.include?("#"))
    end

    def add_docid(id, path)
      if @docid_cache.key? id
        Giblog.logger.warn do
          "Found same doc id twice (#{id}). Will assign this id to the file #{path} and"\
          "not_ to file #{@docid_cache[id]}."
        end
      end
      @docid_cache[id] = Pathname(path)
    end
  end

  # An preprocessor extension to the Asciidoctor engine that transforms all
  # <<:docid:>> references found in the adoc source into the matching
  # file reference.
  # It is dependent on that its 'docid_cache' has been filled before it is
  # invoked via Asciidoctor.
  class DocidCollector < Asciidoctor::Extensions::Preprocessor
    # The regex that matches docid references in files
    DOCID_REF_REGEX = /<<\s*:docid:\s*(.*?)>>/.freeze

    # a hash of {doc_id => Pathname(src_path)}
    # (Use a class-global docid_cache since asciidoctor creates a new instance
    # for each preprocessor hook)
    @docid_cache = {}

    # A class-global hash of {src_path => [target doc_ids] }
    @docid_deps = {}

    class << self
      attr_reader :docid_cache, :docid_deps

      # execute the first pass to collect all doc ids
      # @param src_root  the path to the source root directory
      def run_pass1(adoc_files:)
        # make sure that we start with a clean id cache and
        # dependency tree
        @docid_cache = {}
        @docid_deps = {}
        p1 = DocidPass1.new(docid_cache: @docid_cache, adoc_files: adoc_files)
        p1.run
      end
    end

    # NOTE: I don't know how to hook into the 'initialize' or if I should
    # let this be, currently it is disabled...
    # def initialize(*everything)
    #   super(everything)
    # end

    # Helper method to shorten calls to docid_cache from instance methods
    def docid_cache
      self.class.docid_cache
    end

    # This hook is called by Asciidoctor once for each document _before_
    # Asciidoctor processes the adoc content.
    #
    # It replaces references of the format <<:docid: ID-1234,Hello >> with
    # references to a resolved relative path.
    def process(document, reader)
      # Add doc as a source dependency for doc ids
      src_path = document.attributes["docfile"]

      # NOTE: the nil check is there to prevent us adding generated
      # asciidoc docs that does not exist in the file system (e.g. the
      # generated index pages). This is a bit hackish and should maybe be
      # done differently
      return if src_path.nil?

      # add this file as a source for dependencies
      docid_deps[src_path] ||= []

      # Convert all docid refs to valid relative refs
      reader.lines.each do |line|
        parse_line(line, src_path)
      end

      # we only care for one ref to a specific target, remove duplicates
      docid_deps[src_path] = docid_deps[src_path].uniq

      # the asciidoctor engine wants the reader back
      reader
    end

    private

    def docid_deps
      self.class.docid_deps
    end

    # parse one line for valid docid references
    def parse_line(line, src_path)
      line.gsub!(DOCID_REF_REGEX) do |_m|
        # parse the ref
        target_id, section, display_str = parse_doc_id_ref(Regexp.last_match(1))
        Giblog.logger.debug { "Found docid ref to #{target_id} in file: #{src_path}..." }
        if docid_cache.key? target_id
          # add the referenced doc id as a target dependency of this document
          docid_deps[src_path] << target_id
          transform_ref(target_id, section, display_str, src_path)
        else
          "<<UNKNOWN_DOC, Could not resolve doc id reference !!!>>"
        end
      end
    end

    # Get the relative path from the src doc to the
    # doc with the given doc id
    def get_rel_path(src_path, doc_id)
      raise ArgumentError("unknown doc id: #{doc_id}") unless docid_cache.key? doc_id

      rel_path = docid_cache[doc_id]
                 .dirname
                 .relative_path_from(Pathname.new(src_path).dirname) +
                 docid_cache[doc_id].basename
      rel_path.to_s
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

    # Transform a :doc_id: reference to its resolved relative path
    #
    # The result is a valid ref in the form
    # <<target_doc.adoc#[section][,display_str]>>
    def transform_ref(target_id, section, display_str, src_path)
      # resolve the doc id ref to a valid relative path
      rel_path = get_rel_path(src_path, target_id)
      # return the transformed ref
      "<<#{rel_path}##{section}#{display_str}>>"
    end
  end

  # Helper method to register the docid preprocessor extension with
  # the asciidoctor engine.
  def self.register_docid_extension
    Asciidoctor::Extensions.register do
      preprocessor DocidCollector
    end
  end
end
