require "pathname"

require_relative "pathutils"

module Giblish
  # Container class for bundling together the data we cache for
  # each asciidoc file we come across
  class DocInfo
    # History info from git
    DocHistory = Struct.new(:date, :author, :message)

    attr_accessor :converted, :doc_id, :purpose_str, :status, :history, :error_msg, :stderr
    attr_reader :title, :rel_path, :src_file

    # these members can have encoding issues when
    # running in a mixed Windows/Linux setting.
    # that is why we explicitly encode them when
    # writing to them

    def title=(rhs)
      @title = rhs.nil? ? nil : rhs.encode("utf-8")
    end

    def src_file=(rhs)
      @src_file = rhs.nil? ? nil : rhs.encode("utf-8")
    end

    def initialize(adoc: nil, dst_root_abs: nil, adoc_stderr: "")
      @src_file = nil
      @history = []
      @converted = true
      @stderr = adoc_stderr
      return unless adoc

      # Get the purpose info if it exists
      @purpose_str = get_purpose_info adoc

      # fill in doc meta data
      self.title = (adoc.doctitle)
      src_dir = adoc.base_dir

      d_attr = adoc.attributes
      self.src_file = (d_attr["docfile"])
      @doc_id = d_attr["docid"]
      return if dst_root_abs.nil?

      # Get the relative path beneath the root dir to the doc
      @rel_path = Pathname.new(
        "#{src_dir}/#{d_attr["docfile"]}".encode("utf-8")
      ).relative_path_from(dst_root_abs)
    end

    def to_s
      "DocInfo: title: #{@title} src_file: #{@src_file}"
    end

    private

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

  # convenience class for initiating DocInfos from conversions of
  # adoc source to target format
  class DocInfoStore
    attr_reader :doc_infos

    # path_manager:: a PathManager instance containing relevant paths for
    # this run of giblish
    def initialize(path_manager)
      @doc_infos = []
      @paths = path_manager
    end

    # Build a PathTree from all absolute paths of the stored
    # DocInfo objects and the associated DocInfo as the data.
    #
    # return::  the built Pathtree sorted with leafs first for each level
    def pathtree
      tree = nil
      @doc_infos.each do |d|
        next unless d.converted

        p = (@paths.src_root_abs.basename / d.rel_path).to_s
        if tree.nil?
          tree = PathTree.new(p, d)
          next
        end

        tree.add_path(p, d)
      end
      return nil if tree.nil?

      # sort the tree
      tree.sort_leaf_first
      tree
    end

    # creates a DocInfo instance, fills it with basic info and
    def add_success(adoc, adoc_stderr)
      Giblog.logger.debug do
        "Adding adoc: #{adoc} Asciidoctor stderr: #{adoc_stderr}\n"\
        "Doc attributes: #{adoc.attributes}"
      end

      info = DocInfo.new(adoc: adoc, dst_root_abs: @paths.dst_root_abs, adoc_stderr: adoc_stderr)
      @doc_infos << info
      info
    end

    def add_fail(filepath, exception)
      info = DocInfo.new

      # the only info we have is the source file name
      info.converted = false
      info.src_file = filepath.to_s
      info.error_msg = exception.message

      @doc_infos << info
      info
    end
  end
end
