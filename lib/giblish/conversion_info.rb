# frozen_string_literal: true

require "pathname"

require_relative "pathutils"

module Giblish
  # Container class for bundling together the data we cache for
  # each asciidoc file we come across
  class ConversionInfo
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

    def initialize(adoc: nil, src_node: nil, dst_node: nil, dst_top: nil, adoc_stderr: "")
      @src_file = nil
      @history = []
      @converted = true
      @stderr = adoc_stderr
      return unless adoc

      # Get the purpose info if it exists
      @purpose_str = get_purpose_info adoc

      # fill in doc meta data
      d_attr = adoc.attributes
      self.title = (adoc.doctitle)
      self.src_file = (d_attr["docfile"])
      @doc_id = d_attr["docid"]
      return if dst_node.nil?

      # Get the relative path beneath the root dir to the src doc
      @rel_path = dst_node.relative_path_from(dst_top).dirname / src_node.pathname.basename
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
end
