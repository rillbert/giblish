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
    attr_accessor :doc_id
    attr_accessor :purpose_str
    attr_accessor :status
    attr_accessor :history
    attr_accessor :error_msg
    attr_accessor :stderr

    # these members can have encoding issues when
    # running in a mixed Windows/Linux setting.
    # that is why we explicitly encodes them when
    # writing to them
    def title
      @title
    end
    def title=(rhs)
      @title = rhs.nil? ? nil : rhs.encode("utf-8")
    end
    def rel_path
      @rel_path
    end
    # attr_accessor :rel_path
    def src_file
      @src_file
    end
    def src_file=(rhs)
      @src_file = rhs.nil? ? nil : rhs.encode("utf-8")
    end
    # attr_accessor :src_file

    # def relPath_utf8
    #   return nil if @rel_path.nil?
    #   @rel_path.to_s.encode("utf-8")
    # end
    #
    # def srcFile_utf8
    #   return nil if @src_file.nil?
    #   @src_file.to_s.encode("utf-8")
    # end

    def initialize(adoc: nil, dst_root_abs: nil, adoc_stderr: "")
      @src_file = nil
      @history = []
      @converted = true
      @stderr = adoc_stderr
      return unless adoc

      # Get the purpose info if it exists
      @purpose_str = get_purpose_info adoc

      # fill in doc meta data
      d_attr = adoc.attributes
      self.src_file=(d_attr["docfile"])
      self.title=(adoc.doctitle)
      @doc_id = d_attr["docid"]
      return if dst_root_abs.nil?

      # Get the relative path beneath the root dir to the doc
      @rel_path = Pathname.new(
          "#{d_attr['outdir']}/#{d_attr['docname']}#{d_attr['docfilesuffix']}".encode("utf-8")
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