require "pathname"

module Giblish
  # Container class for bundling together the data we cache for
  # each asciidoc file we come across
  class DocInfo
    # Cache git info
    class DocHistory
      attr_accessor :date
      attr_accessor :author
      attr_accessor :message
    end

    attr_accessor :converted
    attr_accessor :title
    attr_accessor :doc_id
    attr_accessor :purpose_str
    attr_accessor :status
    attr_accessor :rel_path
    attr_accessor :src_file
    attr_accessor :history
    attr_accessor :error_msg
    attr_accessor :stderr

    # these two members can have encoding issues when
    # running in a mixed Windows/Linux setting.
    # that is why the explicit utf-8 read methods are
    # provided.
    attr_accessor :relPath
    attr_accessor :srcFile

    def relPath_utf8
      return nil if @relPath.nil?
      @relPath.to_s.encode("utf-8")
    end

    def srcFile_utf8
      return nil if @srcFile.nil?
      @srcFile.to_s.encode("utf-8")
    end

    def initialize(adoc: nil, dst_root_abs: nil, adoc_stderr: "")
      @srcFile = nil
      @history = []
      @converted = true
      @stderr = adoc_stderr
      return unless adoc

      # Get the purpose info if it exists
      @purpose_str = get_purpose_info adoc

      # fill in doc meta data
      d_attr = adoc.attributes
      @doc_id = d_attr["docid"]
      @src_file = d_attr["docfile"]
      @title = adoc.doctitle
      return if dst_root_abs.nil?

      # Get the relative path beneath the root dir to the doc
      @rel_path = Pathname.new(
          "#{d_attr['outdir']}/#{d_attr['docname']}#{d_attr['docfilesuffix']}"
      ).relative_path_from(dst_root_abs)
    end

    def to_s
      "DocInfo: title: #{@title} src_file: #{@src_file}"
    end

    private

    def get_purpose_info(adoc)
      # Get the 'Purpose' section if it exists
      purpose_str = ""
      adoc.blocks.each do |section|
        next unless section.is_a?(Asciidoctor::Section) &&
            (section.level == 1) &&
            (section.name =~ /^Purpose$/)

        # filter out 'odd' text, such as lists etc...
        section.blocks.each do |bb|
          next unless bb.is_a?(Asciidoctor::Block)
          purpose_str << "#{bb.source}\n+\n"
        end
      end
      purpose_str
    end
  end
end