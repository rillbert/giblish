require "pathname"
require_relative "pathtree"

module Giblish
  class SubtreeSrcItf
    attr_reader :adoc_source
    def initialize(dst_node, output_basename)
      raise NotImplementedError
    end
  end

  class SubtreeInfoBuilder
    attr_accessor :docattr_provider

    DEFAULT_BASENAME = "index"

    # docattr_provider:: an object implementing the DocAttributesBase interface
    # api_opt_provider:: an object implementing the api_options(dst_top) interface
    # adoc_src_provider:: a Class or object implementing the SubtreeSrcItf interface
    # basename:: the name of the output file that is generated in each directory
    def initialize(docattr_provider = nil, api_opt_provider = nil, adoc_src_provider = nil, basename = DEFAULT_BASENAME)
      @docattr_provider = docattr_provider
      @api_opt_provider = api_opt_provider
      @adoc_src_provider = adoc_src_provider || SubtreeIndexBase
      @basename = basename
      @adoc_source = nil
    end

    def document_attributes(src_node, dst_node, dst_top)
      @docattr_provider.nil? ? {} : @docattr_provider.document_attributes(src_node, dst_node, dst_top)
    end

    def api_options(src_node, dst_node, dst_top)
      @api_opt_provider.nil? ? {} : @api_opt_provider.api_options(dst_top)
    end

    def adoc_source(src_node, dst_node, dst_top)
      @adoc_source
    end

    # Called from TreeConverter during post build phase
    #
    # adds a 'index' node for each directory in the source tree
    # and convert that index using the options from the provider
    # objects given at instantiation of this object
    def on_postbuild(src_tree, dst_tree, converter)
      dst_tree.traverse_preorder do |level, dst_node|
        # we only care about directories
        next if dst_node.leaf?

        # get the relative path to the index dir from the top dir
        index_dir = dst_node.pathname.relative_path_from(dst_tree.pathname).cleanpath
        Giblog.logger.debug { "Creating #{@basename} under #{index_dir}" }

        # get the adoc source from the provider (Class or instance)
        @adoc_source = if @adoc_src_provider.is_a?(Class)
          @adoc_src_provider.new(dst_node, @basename).adoc_source
        else
          @adoc_src_provider.adoc_source
        end

        # add a virtual 'index.adoc' node as the only node in a source tree
        # with this object as source for conversion options
        # and adoc_source
        v_path = Pathname.new("/virtual") / index_dir / "#{@basename}.adoc"
        v_tree = PathTree.new(v_path, self)
        src_node = v_tree.node(v_path, from_root: true)

        # add the destination node where the converted file will be stored
        i_node = dst_node.add_descendants(@basename)

        # do the conversion
        converter.convert(src_node, i_node, dst_tree)
      end
    end
  end
end
