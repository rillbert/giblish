# frozen_string_literal: true

require_relative "pathtree"

module Giblish
  # See https://stackoverflow.com/a/746274 for info on a nice register imp

  class PostProcessors
    attr_reader :processors

    def initialize(docinfo_store, paths, converter)
      @docinfo_store = docinfo_store
      @paths = paths
      @converter = converter
      @processors = []
    end

    def add_instance(object)
      @processors << object
    end

    def add(type)
      @processors << type.new
    end

    # runs all post processors, one at the time.
    # converts the output adoc source pathtree to real files
    def run(adoc_logger)
      @processors.each do |instance|
        result_tree = instance.process(@docinfo_store.pathtree, @paths)
        result_tree&.traverse_preorder do |_level, node|
          next unless node.data

          # TODO: Fix this hack to remove the root dir...
          output = "#{@paths.dst_root_abs / node.pathname.dirname.relative_path_from(@paths.src_root_abs.basename)}/"
          @converter.convert_str(node.data, output, node.segment, logger: adoc_logger)
        end
      end
    end
  end

  # base-class of the interface
  class PostProcessor
    # @param tree   a PathTree containing all files relevant for this
    #               postprocessor.
    # @param paths  a PathManager instance with all relevant paths
    # @return       a pathtree where each non-nil node data is the string
    #               that shall be generated there
    def process(tree, paths)
    end
  end
end
