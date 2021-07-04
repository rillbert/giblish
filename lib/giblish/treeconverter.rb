require "asciidoctor"
require "asciidoctor-pdf"
require_relative "pathtree"

module Giblish
  # Converts all nodes in the supplied src PathTree from adoc to the format
  # given by the user.
  #
  # Requires that all leaf nodes has a 'data' member that can receive an
  # 'adoc_source' method that returns a string with the source to be converted.
  class TreeConverter
    attr_reader :dst_tree

    # see https://docs.asciidoctor.org/asciidoc/latest/attributes/document-attributes-reference/
    DEFAULT_ADOC_DOC_ATTRIBS = {
      "data-uri" => true,
      "hide-uri-scheme" => true,
      "xrefstyle" => "short",
      "source-highlighter" => "rouge",
      "source-linenums-option" => true
      # linkcss et al TBD
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
      @pre_builders = []
      @src_top = src_top
      @pre_builders = Array(opts.fetch(:pre_builders, []))
      @post_builders = Array(opts.fetch(:post_builders, []))
      @dst_tree = PathTree.new(dst_top, {})
      @dst_top = @dst_tree.node(dst_top, from_root: true)
      @logger = opts.fetch(:logger, nil)
      @adoc_log_level = opts.fetch(:adoc_log_level, Logger::Severity::WARN)
      @conv_cb = opts.fetch(:conversion_cb, {})

      # merge user's options with the default, giving preference
      # to the user
      # .merge!({logger: adoc_logger})
      @adoc_api_opts = DEFAULT_ADOC_OPTS.dup
        .merge!(opts.fetch(:adoc_api_opts, {}))
      @adoc_api_opts[:attributes] = DEFAULT_ADOC_DOC_ATTRIBS.dup
        .merge!(opts.fetch(:adoc_doc_attribs, {}))

      # setup adoc extensions
      register_adoc_extensions(opts[:adoc_extensions]) if opts[:adoc_extensions]
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

    private

    # register all asciidoctor extensions given at instantiation
    #
    # adoc_ext::
    # { preprocessor: [], ... }
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

    # require the following methods to be available from the node:
    # adoc_source
    #
    # the following methods will be called if supported:
    # document_attributes
    # api_options
    def convert(node, dst_tree)
      @logger&.info { "Converting #{node.pathname}..." }

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
          @adoc_api_opts.merge({
            parse: false,
            logger: adoc_logger
          })
        )

        # get dst path
        q = node.pathname.relative_path_from(@src_top.pathname).sub_ext(doc.attributes["outfilesuffix"])

        # create the destination
        dst_node = @dst_top.add_descendants(q)
        d = dst_node.pathname

        # piggy-back our own info on the doc attributes hash so that
        # asciidoctor extensions can use this info
        doc.attributes["giblish-src-tree-node"] = node

        # make sure the dst dir exists
        d.dirname.mkpath

        # write the converted doc to the file
        output = doc.convert(@adoc_api_opts.merge({logger: adoc_logger}))
        doc.write(output, d.to_s)

        # give user the opportunity to eg store the result of the conversion
        # as data in the destination node
        @conv_cb[:success]&.call(node, dst_node, doc, adoc_logger.in_mem_storage.string)
        true
      rescue => e
        @logger&.error { e.message }
        @conv_cb[:failure]&.call(node, dst_node, e, adoc_logger.in_mem_storage.string)
        false
      end
    end
  end
end
