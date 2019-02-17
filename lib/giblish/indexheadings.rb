require "json"
require "pathname"
require "asciidoctor"
require "asciidoctor/extensions"
require_relative "./utils"

module Giblish

  # This hook is called by Asciidoctor once for each document _before_
  # Asciidoctor processes the adoc content.
  #
  # It indexes all headings found in all documents in the tree.
  # The resulting index can be serialized to a JSON file file
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
  class IndexHeadings < Asciidoctor::Extensions::Preprocessor

    # Use a class-global heading_index dict since asciidoctor creates a new instance
    # of this class for each processed file
    @heading_index = {"file_infos" => []}

    class << self
      def heading_index
        @heading_index
      end

      def clear_index
        @heading_index = {"file_infos" => []}
      end

      # write the index to a file in dst_dir and remove the base_dir
      # part of the path for each filename
      def serialize(dst_dir, base_dir = "")
        dst_dir = Pathname.new(dst_dir) unless dst_dir.respond_to?(:join)
        base_dir = Pathname.new(base_dir) unless base_dir.respond_to?(:join)

        if base_dir.to_s.empty?
          heading_index
        else
          # remove the base_dir part of the file path
          heading_index["file_infos"].each do |file_info|
            file_info["filepath"] = Pathname.new(file_info["filepath"])
                                        .relative_path_from(base_dir)
          end
        end

        Giblog.logger.info { "writing json to #{dst_dir.join("heading_index.json").to_s}" }
        File.open(dst_dir.join("heading_index.json").to_s,"w") do |f|
          f.write(heading_index.to_json)
        end
      end
    end

    def process(document, reader)
      # Add doc as a source dependency for doc ids
      src_path = document.attributes["docfile"]

      # Note: the nil check is there to prevent us adding generated
      # asciidoc docs that does not exist in the file system (e.g. the
      # generated index pages). This is a bit hackish and should maybe be
      # done differently
      return if src_path.nil?

      # get the title from thw raw text (asciidoctor has not yet
      # processed the text)
      title = find_title reader.lines

      # Index all headings in the doc
      Giblog.logger.debug { "indexing headings in #{src_path}" }
      sections = []
      file_info_hash = {
          "filepath" => src_path,
          "title" => title,
          "sections" => sections
      }

      # build the 'sections' array
      line_no = 1
      regex = Regexp.new(/^=+\s+(.*)$/)
      reader.lines.each do |line|
        m = regex.match(line)
        if m
          # We found a heading, index it
          section = { "id" => get_unique_id(file_info_hash, m[1]) }
          section["title"] = m[1].strip
          section["line_no"] = line_no
          sections << section
        end
        line_no += 1
      end

      heading_index["file_infos"] << file_info_hash
      reader
    end

    private

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
