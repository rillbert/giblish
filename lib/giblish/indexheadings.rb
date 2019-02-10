require "json"
require "asciidoctor"
require "asciidoctor/extensions"
require_relative "./utils"

module Giblish

  # Parse adoc files and index their headings in a global dict
  # The dict looks as:
  # {
  #  file_name_doc_1 => {"heading_1"=>10,"heading_2"=>34, ...},
  #  file_name_doc_2 => {"heading_1"=>4,"heading_2"=>22, ...}
  # }
  class IndexHeadings < Asciidoctor::Extensions::Preprocessor

    # Use a class-global heading_index dict since asciidoctor creates a new instance
    # of this class for each preprocessor hook call
    @heading_index = {}

    class << self
      def heading_index
        @heading_index
      end

      def clear_index
        @heading_index = {}
      end

      def serialize dir_path
        puts "writing json to #{dir_path.join("heading_index.json").to_s}"
        File.open(dir_path.join("heading_index.json").to_s,"w") do |f|
          f.write(@heading_index.to_json)
        end
      end
    end

    # scan through a document and index all its headings
    #
    # a heading is defined as a line starting with one or more
    # '=' signs. Note that the 'old style' is not supported.
    def parse_file(path)

    end

    # This hook is called by Asciidoctor once for each document _before_
    # Asciidoctor processes the adoc content.
    #
    # It indexes all headings found in the document in a dictionary
    def process(document, reader)
      # Add doc as a source dependency for doc ids
      src_path = document.attributes["docfile"]

      # Note: the nil check is there to prevent us adding generated
      # asciidoc docs that does not exist in the file system (e.g. the
      # generated index pages). This is a bit hackish and should maybe be
      # done differently
      return if src_path.nil?

      # Index all headings in the doc
      Giblog.logger.debug { "indexing headings in #{src_path}" }
      line_no = 1
      doc_heading_dict = {}
      reader.lines.each do |line|
        m = /^=+\s+(.*)$/.match(line)
        if m
          # We found a heading, index it
          doc_heading_dict[get_unique_id(doc_heading_dict, m[1])] = line_no
        end
        line_no += 1
      end
      heading_index[src_path] = doc_heading_dict
      Giblog.logger.info {"index: #{heading_index.inspect}"}
      reader
    end

    private

    def get_unique_id(doc_heading_dict, heading_str)
      id_base = Giblish.to_valid_id(heading_str)
      return id_base if !doc_heading_dict.key? id_base

      # handle the case with several sections with the same name
      idx = 1
      heading_id = ""
      loop do
        idx += 1
        heading_id = "#{id_base}_#{idx}"
        # some code here
        break unless doc_heading_dict.key? heading_id
      end
      return heading_id
    end

    # Helper method to shorten calls to the heading_index from instance methods
    def heading_index
      self.class.heading_index
    end
  end


  # Helper method to register the docid preprocessor extension with
  # the asciidoctor engine.
  def register_index_heading_extension
    Asciidoctor::Extensions.register do
      preprocessor IndexHeadings
    end
  end
  module_function :register_index_heading_extension
end
