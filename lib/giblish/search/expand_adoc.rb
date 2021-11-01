require "asciidoctor"

module Giblish
  # Expands any 'include' preprocessor directives found in the given document
  # and merges the the lines in the included document with the ones
  # from the including document.
  # Nesting of includes is supported to the given level.
  #
  # NOTE: Only includes of asciidoc files are supported, other includes (eg url)
  # are silently dropped.
  class ExpandAdoc
    IncludeDirectiveRx = /^(\\)?include::([^\[][^\[]*)\[(.+)?\]$/
    def initialize(document, target_lines, max_depth = 3)
      source_lines = document.reader.source_lines
      source_lines.each do |line|
        if IncludeDirectiveRx =~ line
          next unless max_depth > 0

          p = resolve_include_path(document, $2, $3)
          next if p.nil?

          sub_doc = Asciidoctor.load_file(p, {parse: false, safe: :unsafe})
          ExpandAdoc.new(sub_doc, target_lines, max_depth - 1)
        else
          target_lines << wash_line(document, line)
        end
      end
    end

    def resolve_include_path(document, target, attrlist)
      target = replace_attrs(document.attributes, target)
      parsed_attrs = document.parse_attributes attrlist, [], sub_input: true

      # use an asciidoctor-internal method to resolve the path in an attempt to keep compatibility
      inc_path, target_type, _relpath = document.reader.send(:resolve_include_path, target, attrlist, parsed_attrs)
      return nil unless target_type == :file

      inc_path
    end

    def wash_line(document, line)
      replace_attrs(document.attributes, line)
    end

    # replace {a_doc_attr} with the value of the attribute
    def replace_attrs(attrs, line)
      # find all '{...}' occurrences
      m_arr = line.scan(/\{\w+\}/)
      # replace each found occurence with its doc attr if exists
      m_arr.inject(line) do |memo, match|
        attrs.key?(match[1..-2]) ? memo.gsub(match.to_s, attrs[match[1..-2]]) : memo
      end
    end
  end
end
