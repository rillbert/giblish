
module Giblish
  # An preprocessor extension to the Asciidoctor engine that transforms all
  # <<:docid:>> references found in the adoc source into the matching
  # file reference.
  # It is dependent on that its 'docid_cache' has been filled before it is
  # invoked via Asciidoctor.
  class DocidCollector < Asciidoctor::Extensions::Preprocessor
    # The regex that matches docid references in files
    DOCID_REF_REGEX = /<<\s*:docid:\s*(.*?)>>/.freeze

    # A class-global hash of {src_path => [target doc_ids] }
    @docid_deps = {}

    # This hook is called by Asciidoctor once for each document _before_
    # Asciidoctor processes the adoc content.
    #
    # It replaces references of the format <<:docid: ID-1234,Hello >> with
    # references to a resolved relative path.
    def process(document, reader)
      # Add doc as a source dependency for doc ids
      src_path = document.attributes["docfile"]

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
          Giblog.logger.warn { "Could no resolve ref to #{target_id} from file: #{src_path}..." }
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
