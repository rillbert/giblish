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

      @pre_builders = []
      @pre_builders = Array(opts.fetch(:pre_builders, []))
      @post_builders = Array(opts.fetch(:post_builders, []))
      @logger = opts.fetch(:logger, Giblog.logger)
      @adoc_log_level = opts.fetch(:adoc_log_level, Logger::Severity::WARN)
      @conv_cb = opts.fetch(:conversion_cb, {
        success: ->(src, dst, dst_rel_path, doc, logstr) { on_success(src, dst, dst_rel_path, doc, logstr) },
        failure: ->(src, dst, dst_rel_path, ex, logstr) { on_failure(src, dst, dst_rel_path, ex, logstr) }
      })

      # merge user's options with the default, giving preference
      # to the user
      # .merge!({logger: adoc_logger})
      @adoc_api_opts = DEFAULT_ADOC_OPTS.dup
        .merge!(opts.fetch(:adoc_api_opts, {}))
      @adoc_api_opts[:attributes] = DEFAULT_ADOC_DOC_ATTRIBS.dup
        .merge!(opts.fetch(:adoc_doc_attribs, {}))

      # setup adoc extensions
      # register_adoc_extensions(opts[:adoc_extensions]) if opts[:adoc_extensions]
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

        ok = convert(n, @dst_tree) && ok
      end
      ok
    end

    def post_build
      @dst_tree.traverse_preorder do |level, n|
        @post_builders.each { |pp| pp.run(n) }
      end
    end

    def on_success(src_node, dst_node, dst_top, doc, adoc_log_str)
      dst_node.data = ConversionInfo.new(
        adoc: doc, src_node: src_node, dst_node: dst_node, dst_top: dst_top, adoc_stderr: adoc_log_str
      )
    end

    def on_failure(src_node, dst_node, dst_top, ex, adoc_log_str)
      @logger&.error { ex.message }
      # the only info we have is the source file name
      info = ConversionInfo.new
      info.converted = false
      info.src_file = src_node.pathname.to_s
      info.error_msg = ex.message

      dst_node.data = info unless dst_node.nil?
    end

    private

    # require the following methods to be available from the node:
    # adoc_source
    #
    # the following methods will be called if supported:
    # document_attributes
    # api_options
    def convert(node, dst_tree)
      @logger&.info { "Converting #{node.pathname}..." }

      puts node.api_options.inspect if node.respond_to?(:api_options)
      puts node.document_attributes.inspect if node.respond_to?(:document_attributes)

      # merge the common api opts with node specific
      api_opts = @adoc_api_opts.dup
      api_opts.merge!(node.api_options) if node.respond_to?(:api_options)
      api_opts[:attributes].merge!(node.document_attributes) if node.respond_to?(:document_attributes)

      # use a new logger instance for each conversion
      adoc_logger = Giblish::AsciidoctorLogger.new(@adoc_log_level)
      dst_node = nil

      begin
        # load the source and parse it to enable access to doc
        # properties
        # NOTE: the 'parse: false' is needed to prevent preprocessor extensions to be run as part
        # of loading the document. We want them to run during the 'convert' call later when
        # doc attribs have been amended.
        doc = Asciidoctor.load(
          node.adoc_source,
          api_opts.merge({
            parse: false,
            logger: adoc_logger
          })
        )

        # create the destination node, using the correct suffix depending on conversion backend
        rel_path = node.relative_path_from(@src_top)
        dst_node = @dst_top.add_descendants(rel_path.sub_ext(doc.attributes["outfilesuffix"]))
        d = dst_node.pathname

        # piggy-back our own info on the doc attributes hash so that
        # asciidoctor extensions can use this info
        doc.attributes["giblish-src-tree-node"] = node

        # make sure the dst dir exists
        d.dirname.mkpath

        # write the converted doc to the file
        output = doc.convert(api_opts.merge({logger: adoc_logger}))
        doc.write(output, d.to_s)

        # give user the opportunity to eg store the result of the conversion
        # as data in the destination node
        @conv_cb[:success]&.call(node, dst_node, @dst_top, doc, adoc_logger.in_mem_storage.string)
        true
      rescue => ex
        @logger&.error { ex.message }
        @logger&.error { ex.backtrace }
        @conv_cb[:failure]&.call(node, dst_node, @dst_top, ex, adoc_logger.in_mem_storage.string)
        false
      end
    end
  end
end
