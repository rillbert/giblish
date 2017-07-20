
require_relative "./utils.rb"

module Giblish
  # Parse all adoc files for :docid: attributes
  class DocidCollector
    attr_reader :docid_cache
    IDMinLength = 2
    IDMaxLength = 10

    def initialize
      # array with one hash for each discovered docid
      @docid_cache = {}
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
        Giblog.logger.debug { "parsing header line #{line}" }
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
          validate_and_add m[1],path
        end
      end
    end

    def substitute_ids(src_str)
      src_str.gsub!(/<<\s*:docid:(.*)>>/) do |_m|
        replace_doc_id Regexp.last_match(1)
      end
    end

    private

    # The input string shall contain the expression between
    # <<:docid:<input_str>>> where the <input_str> is in the form
    # <id>#RefTitle
    #
    # The result shall be a valid ref in the form
    # <<target_doc.adoc#RefTitle>>
    def replace_doc_id(input_str)
      id, ref_title = input_str.split "#"
      ref_title = "" if ref_title.nil?
      ref_title.prepend "#"

      if @docid_cache.key? id
        "<<#{@docid_cache[id]}#{ref_title}>>"
      else
        Giblog.logger.error { "Unknown docid: #{id}" }
        "<<UNKNOWN_DOC#{ref_title}>>"
      end
    end

    def validate_and_add(doc_id, path)
      id = doc_id.strip
      Giblog.logger.debug { "found possible docid: #{id}" }

      # make sure the id is within the designated length and
      # does not contain a '#' symbol
      if id.length.between?(IDMinLength, IDMaxLength) &&
         !id.include?("#")
        # the id is ok
        @docid_cache[id] = path
      else
        Giblog.logger.error { "Invalid docid: #{id}, this will be ignored!" }
      end
    end
  end
end
# Usage:
# This doc references docref:A-1234[A-1234] for info on hippos.
# class DocRefInlineMacro < Asciidoctor::Extensions::InlineMacroProcessor
#   use_dsl
#
#   named :docref
#   name_positional_attributes "display_text"
#
#   def process parent, target, attrs
#     # puts "parent: #{parent}"
#     # puts "target: #{target}"
#     # puts "attrs: #{attrs}"
#     puts "docref macro called!"
#     rel_path = Giblish.DocRefCache.rel_path(target)
#     target = %(<<rel_path#,attrs[display_text]>>)
#     parent.document.register :links, target
#     %(#{(create_anchor parent, text, type: :link, target: target).convert}#{suffix})
#   end
# end
