require "asciidoctor"
require "asciidoctor-pdf"
require_relative "pathtree"
require_relative "conversion_info"

module Giblish
  # Converts all nodes in the supplied src PathTree from adoc to the format
  # given by the user.
  #
  # Requires that all leaf nodes has a 'data' member that can receive an
  # 'adoc_source' method that returns a string with the source to be converted.
  class TreeConverter
    attr_reader :dst_tree

    class << self
      # register all asciidoctor extensions given at instantiation
      #
      # adoc_ext::
      # { preprocessor: [], ... }
      #
      # see https://docs.asciidoctor.org/asciidoctor/latest/extensions/register/
      def register_adoc_extensions(adoc_ext)
        %i[preprocessor tree_processor postprocessor docinfo_processor block
          block_macro inline_macro include_processor].each do |e|
          next unless adoc_ext.key?(e)

          Array(adoc_ext[e])&.each do |c|
            Asciidoctor::Extensions.register { send(e, c) }
          end
        end
      end
    end

    # opts:
    #  logger: the logger used internally by this instance (default nil)
    #  adoc_log_level - the log level when logging messages emitted by asciidoctor
    #  (default Logger::Severity::WARN)
    #  pre_builders
    #  post_builders
    #  adoc_api_opts
    #  adoc_doc_attribs
    #  conversion_cb {success: Proc(src,dst,adoc) fail: Proc(src,dst,exc)
    def initialize(src_top, dst_top, opts = {})
      init_src_dst(src_top, dst_top)
      @pre_builders = Array(opts.fetch(:pre_builders, []))
      @post_builders = Array(opts.fetch(:post_builders, []))
      @logger = opts.fetch(:logger, Giblog.logger)
      @adoc_log_level = opts.fetch(:adoc_log_level, Logger::Severity::WARN)
      @converter = DefaultConverter.new(@logger,opts)
    end

    def init_src_dst(src_top, dst_top)
      @src_top = src_top
      @dst_tree = PathTree.new(dst_top, {})
      @dst_top = @dst_tree.node(dst_top, from_root: true)
      self
    end

    def run
      pre_build
      build
      post_build
    end

    def pre_build
      @src_top.traverse_preorder do |level, n|
        @pre_builders.each { |pp| pp.run(n) }
      end
    end

    def build
      ok = true
      @src_top.traverse_preorder do |level, n|
        next unless n.leaf?

        # create the destination node, using the correct suffix depending on conversion backend
        rel_path = n.relative_path_from(@src_top)
        dst_node = @dst_top.add_descendants(rel_path.sub_ext(''))

        # perform the conversion
        ok = @converter.convert(n, dst_node, @dst_top) && ok
      end
      ok
    end

    def post_build
      @post_builders.each { |pb| pb.run(@src_tree, @dst_tree, @converter)}
    end

    def self.on_success(src_node, dst_node, dst_top, doc, adoc_log_str)
      dst_node.data = ConversionInfo.new(
        adoc: doc, src_node: src_node, dst_node: dst_node, dst_top: dst_top, adoc_stderr: adoc_log_str
      )
    end

    def self.on_failure(src_node, dst_node, dst_top, ex, adoc_log_str)
      @logger&.error { ex.message }
      # the only info we have is the source file name
      info = ConversionInfo.new
      info.converted = false
      info.src_file = src_node.pathname.to_s
      info.error_msg = ex.message

      dst_node.data = info unless dst_node.nil?
    end
  end

  class DefaultConverter
    attr_accessor :adoc_api_opts
    # see https://docs.asciidoctor.org/asciidoc/latest/attributes/document-attributes-reference/
    DEFAULT_ADOC_DOC_ATTRIBS = {
      "data-uri" => true,
      "hide-uri-scheme" => true,
      "xrefstyle" => "short",
      "source-highlighter" => "rouge",
      "source-linenums-option" => true
    }

    # see https://docs.asciidoctor.org/asciidoctor/latest/api/options/
    DEFAULT_ADOC_OPTS = {
      backend: "html5",
      # base_dir:
      catalog_assets: false,
      # converter:
      doctype: "article",
      # eruby:
      # ignore extention stuff
      header_only: false,
      logger: Giblish::AsciidoctorLogger.new(Logger::Severity::WARN),
      mkdirs: false,
      parse: true,
      safe: :unsafe,
      sourcemap: false,
      # template stuff TBD,
      # to_file:
      # to_dir:
      standalone: true
    }

    # opts:
    #  adoc_log_level
    #  adoc_api_opts
    #  adoc_doc_attribs
    #  conversion_cb { 
    #     success: lambda(src, dst, dst_rel_path, doc, logstr)
    #     fail: lambda(src,dst,exc)
    #  }
    def initialize(logger, opts)
      @logger = logger
      @adoc_log_level = opts.fetch(:adoc_log_level, Logger::Severity::WARN)
      @conv_cb = opts.fetch(:conversion_cb, {
        success: ->(src, dst, dst_rel_path, doc, logstr) { TreeConverter.on_success(src, dst, dst_rel_path, doc, logstr) },
        failure: ->(src, dst, dst_rel_path, ex, logstr) { TreeConverter.on_failure(src, dst, dst_rel_path, ex, logstr) }
      })

      # merge user's options with the default, giving preference
      # to the user
      @adoc_api_opts = DEFAULT_ADOC_OPTS.dup
        .merge!(opts.fetch(:adoc_api_opts, {}))
      @adoc_api_opts[:attributes] = DEFAULT_ADOC_DOC_ATTRIBS.dup
        .merge!(opts.fetch(:adoc_doc_attribs, {}))
    end

    # require the following methods to be available from the src node:
    # adoc_source
    #
    # the following methods will be called if supported:
    # document_attributes
    # api_options
    #
    # src_node:: the PathTree node containing the info on adoc source and any
    # added api_options or doc_attributes
    # dst_node:: the PathTree node where conversion info is to be stored
    # dst_top:: the PathTree node representing the top dir of the destination
    # under which all converted files are written.
    def convert(src_node, dst_node, dst_top)
      @logger&.info { "Converting #{src_node.pathname} and store result under #{dst_node.parent.pathname}" }

      # merge the common api opts with node specific
      api_opts = @adoc_api_opts.dup
      api_opts.merge!(src_node.api_options) if src_node.respond_to?(:api_options)
      api_opts[:attributes].merge!(src_node.document_attributes) if src_node.respond_to?(:document_attributes)

      # use a new logger instance for each conversion
      adoc_logger = Giblish::AsciidoctorLogger.new(@adoc_log_level)

      begin
        # load the source and parse it to enable access to doc
        # properties
        # NOTE: the 'parse: false' is needed to prevent preprocessor extensions to be run as part
        # of loading the document. We want them to run during the 'convert' call later when
        # doc attribs have been amended.
        doc = Asciidoctor.load(src_node.adoc_source, api_opts.merge(
          {
            parse: false,
            logger: adoc_logger
          }
        ))

        # piggy-back our own info on the doc attributes hash so that
        # asciidoctor extensions can use this info
        doc.attributes["giblish-src-tree-node"] = src_node

        # update the destination node with the correct file suffix. This is dependent
        # on the type of conversion performed
        dst_node.name = dst_node.name.sub_ext(doc.attributes["outfilesuffix"])
        d = dst_node.pathname

        # make sure the dst dir exists
        d.dirname.mkpath

        # write the converted doc to the file
        output = doc.convert(api_opts.merge({logger: adoc_logger}))
        doc.write(output, d.to_s)

        # give user the opportunity to eg store the result of the conversion
        # as data in the destination node
        @conv_cb[:success]&.call(src_node, dst_node, dst_top, doc, adoc_logger.in_mem_storage.string)
        true
      rescue => ex
        @logger&.error { ex.message }
        @logger&.error { ex.backtrace }
        @conv_cb[:failure]&.call(src_node, dst_node, dst_top, ex, adoc_logger.in_mem_storage.string)
        false
      end
    end
  end
end
