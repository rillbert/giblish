
require_relative "./utils.rb"

require 'asciidoctor'
require 'asciidoctor/extensions'

module Giblish
  # Parse all adoc files for :docid: attributes
  class DocidCollector < Asciidoctor::Extensions::Preprocessor
    # Use a class-global docid_cache since asciidoctor creates a new Instance
    # for each preprocessor hook
    class << self
      attr_reader :docid_cache
      def clear_cache
        @docid_cache = {}
      end
    end
    @docid_cache = {}

    # The minimum number of characters required for a valid doc id
    ID_MIN_LENGTH = 2

    # The maximum number of characters required for a valid doc id
    ID_MAX_LENGTH = 10

    def initialize
      # array with one hash for each discovered docid
#      @docid_cache = {}
    end

    # Helper method that provides the user with a way of processing only the
    # lines within the asciidoc header block.
    # The user must return nil to get the next line.
    #
    # ex:
    # process_header_lines(file_path) do |line|
    #   if line == "Quack!"
    #      puts "Donald!"
    #      1
    #   else
    #      nil
    #   end
    # end
    def process_header_lines(path)
      state = "before_header"
      File.foreach(path) do |line|
        case state
        when "before_header" then (state = "in_header" if line =~ /^=+.*$/)
        when "in_header" then (state = "done" if line =~ /^\s*$/ || yield(line))
        when "done" then break
        end
      end
    end

    # Check if a :docid: <id> entry exists in the header.
    # According to http://www.methods.co.nz/asciidoc/userguide.html#X95
    # the header is optional, but if it exists it:
    # - must start with a titel (=+ <My Title>)
    # - ends with one or more blank lines
    # - does not contain any blank line
    def parse_file(path)
      Giblog.logger.debug { "parsing file #{path} for docid..." }
      process_header_lines(path) do |line|
        m = /^:docid: +(.*)$/.match(line)
        if m
          # There is a docid defined, cache the path and doc id
          validate_and_add m[1], path
        end
      end
    end

    def process(_document, reader)
      reader.lines.each do |line|
        line.gsub!(/<<\s*:docid:\s*(.*)>>/) do |_m|
          replace_doc_id Regexp.last_match(1), src_path
        end
      end
      reader
    end

    def substitute_ids_file(path)
      substitute_ids(File.read(path), path)
    end

    def substitute_ids(src_str, src_path)
      src_str.gsub!(/<<\s*:docid:\s*(.*)>>/) do |_m|
        replace_doc_id Regexp.last_match(1), src_path
      end
      src_str
    end

    private

    def get_rel_path(src_path, doc_id)
      return "UNKNOWN_DOC" unless @docid_cache.key? doc_id

      rel_path = @docid_cache[doc_id]
                 .dirname
                 .relative_path_from(Pathname.new(src_path).dirname) +
                 @docid_cache[doc_id].basename
      rel_path.to_s
    end

    # The input string shall contain the expression between
    # <<:docid:<input_str>>> where the <input_str> is in the form
    # <id>[#section][,display_str]
    #
    # The result shall be a valid ref in the form
    # <<target_doc.adoc#[section][,display_str]>>
    def replace_doc_id(input_str, src_path)
      ref, display_str = input_str.split(",").each(&:strip)
      display_str = "" if display_str.nil?
      display_str.prepend "," if display_str.length.positive?

      id, section = ref.split "#"
      section = "" if section.nil?

      "<<#{get_rel_path(src_path, id)}##{section}#{display_str}>>"
    end

    def validate_and_add(doc_id, path)
      id = doc_id.strip
      Giblog.logger.debug { "found possible docid: #{id}" }

      # make sure the id is within the designated length and
      # does not contain a '#' symbol
      if id.length.between?(ID_MIN_LENGTH, ID_MAX_LENGTH) &&
         !id.include?("#")
        # the id is ok
        if @docid_cache.key? id
          Giblog.logger.warn { "Found same doc id twice (#{id}). Using last found id."}
        end
        @docid_cache[id] = Pathname(path)
      else
        Giblog.logger.error { "Invalid docid: #{id}, this will be ignored!" }
      end
    end
  end

  def register_extensions
    Asciidoctor::Extensions.register do
      preprocessor DocidCollector
    end
  end

  module_function

end
