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
        result_tree.traverse_top_down do |_level, node|
          next unless node.data

          output = "#{@paths.dst_root_abs / node.pathname.dirname}/"
          @converter.convert_str(node.data, output, node.name, logger: adoc_logger)
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
    def process(tree, paths); end
  end
end

# class DirectoryIndex
#   def initialize(dir_node)
#     @dir_node = dir_node
#   end

#   def source
#     <<~ADOC_STR
#       #{title}

#       #{file_listing}

#     ADOC_STR
#   end

#   private

#   def title
#     "== Listing for #{@dir_node.name}"
#   end

#   def file_listing
#     @dir_node.children.map do |ch|
#       next unless ch.leaf?

#       " * #{ch.name}"
#     end.join("\n")
#   end
# end

# class MySecondPostProcessor
#   def process(tree, _paths)
#     result = PathTree.new
#     tree.traverse_top_down do |_level, node|
#       result.add_path(node.name, "== New Index for #{node.name}")
#     end
#     result
#   end

#   def dst_path
#     "myfile 2"
#   end
# end

# dummyConverter = Class.new do
#   def convert_str(str, file, _logger)
#     puts "would have converted : #{str} to file #{file}"
#   end
# end

# paths = %w[basedir/file_a
#            basedir/index.adoc
#            basedir/dira/index.adoc
#            basedir/dirb/index.adoc
#            basedir2/index.adoc]

# tree = PathTree.new
# count = 1
# paths.each do |p|
#   puts "adding path: #{p}"
#   tree.add_path p, "== Doc #{count}"
#   count += 1
# end

# pp = Giblish::PostProcessors.new(tree, "hopp", dummyConverter.new)
# pp.add(MyPostProcessor)
# pp.add(MySecondPostProcessor)
# pp.add(MyPostProcessor)
# pp.run(nil)
