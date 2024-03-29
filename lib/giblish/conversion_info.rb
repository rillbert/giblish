require "pathname"

module Giblish
  class FileHistory
    # History info from git
    LogEntry = Struct.new(:date, :author, :message, :sha1)

    attr_accessor :history, :branch

    def initialize(branch)
      @branch = branch
      @history = []
    end
  end

  # Base class for bundling together data we always cache for
  # each asciidoc file we come across.
  #
  # Users are expected to use the derived classes.
  class ConversionInfo
    attr_reader :converted, :src_node, :dst_node, :dst_top

    # The relative Pathname from the root dir to the src doc
    # Ex Pathname("my/subdir/file1.adoc")
    attr_reader :src_rel_path

    @@nof_missing_titles = 0

    def initialize(converted:, src_node:, dst_node:, dst_top:)
      @converted = converted
      @src_node = src_node
      @dst_node = dst_node
      @dst_top = dst_top
      @title = nil

      @src_rel_path = dst_node.relative_path_from(dst_top).dirname / src_node.pathname.basename
    end

    # return:: a String with the basename of the source file
    def src_basename
      @src_node.pathname.basename.to_s
    end

    def title
      return @title if @title

      "NO TITLE FOUND (#{@@nof_missing_titles += 1}) !"
    end

    def docid
      nil
    end

    def to_s
      "Conversion #{@converted ? "succeeded" : "failed"} - src: #{@src_node.pathname} dst: #{@dst_node.pathname}"
    end
  end

  # Provide data and access methods available when a conversion has
  # succeeded
  class SuccessfulConversion < ConversionInfo
    attr_reader :stderr, :adoc

    # The relative Pathname from the root dir to the dst file
    # Ex Pathname("my/subdir/file1.html")
    attr_reader :dst_rel_path

    attr_reader :purpose_str

    def initialize(src_node:, dst_node:, dst_top:, adoc:, adoc_stderr: "")
      super(converted: true, src_node: src_node, dst_node: dst_node, dst_top: dst_top)

      @adoc = adoc
      @stderr = adoc_stderr
      @title = @adoc.doctitle

      @dst_rel_path = dst_node.relative_path_from(dst_top)

      # Cach the purpose info if it exists
      @purpose_str = get_purpose_info adoc
    end

    def docid
      @adoc.attributes["docid"]
    end

    private

    # TODO: Move this somewhere else
    def get_purpose_info(adoc)
      # Get the 'Purpose' section if it exists
      purpose_str = +""
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

  # Provide data and access methods available when a conversion has
  # failed
  class FailedConversion < ConversionInfo
    attr_reader :error_msg

    def initialize(src_node:, dst_node:, dst_top:, error_msg: nil)
      super(converted: false, src_node: src_node, dst_node: dst_node, dst_top: dst_top)

      @error_msg = error_msg
    end
  end
end
