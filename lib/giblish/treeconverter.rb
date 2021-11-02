require "asciidoctor"
require "asciidoctor-pdf"
require_relative "pathtree"
require_relative "conversion_info"
require_relative "utils"

module Giblish
  # Converts all nodes in the supplied src PathTree from adoc to the format
  # given by the user.
  #
  # Requires that all leaf nodes has a 'data' member that can receive an
  # 'adoc_source' method that returns a string with the source to be converted.
  #
  # implements three phases with user hooks:
  # pre_build -> build -> post_build
  #
  # Prebuild::
  # add a pre_builder object that responds to:
  # def run(src_tree, dst_tree, converter)
  # where
  # src_tree:: the node in a PathTree corresponding to the top of the
  # src directory
  # dst_tree:: the node in a PathTree corresponding to the top of the
  # dst directory
  # converter:: the specific converter used to convert the adoc source to
  # the desired destination format.

  class TreeConverter
    attr_reader :dst_tree, :pre_builders, :post_builders, :converter

    class << self
      # register all asciidoctor extensions given at instantiation
      #
      # adoc_ext::
      # { preprocessor: [], ... }
      #
      # see https://docs.asciidoctor.org/asciidoctor/latest/extensions/register/
      def register_adoc_extensions(adoc_ext)
        return if adoc_ext.nil?

        %i[preprocessor tree_processor postprocessor docinfo_processor block
          block_macro inline_macro include_processor].each do |e|
          next unless adoc_ext.key?(e)

          Array(adoc_ext[e])&.each do |c|
            Giblog.logger.debug { "Register #{c.class} as #{e}" }
            Asciidoctor::Extensions.register { send(e, c) }
          end
        end
      end

      def unregister_adoc_extenstions
        Asciidoctor::Extensions.unregister_all
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
      # setup logging
      @logger = opts.fetch(:logger, Giblog.logger)
      @adoc_log_level = opts.fetch(:adoc_log_level, Logger::Severity::WARN)

      # get the top-most node of the source and destination trees
      @src_tree = src_top
      @dst_tree = PathTree.new(dst_top).node(dst_top, from_root: true)

      # setup build-phase callback objects
      @pre_builders = Array(opts.fetch(:pre_builders, []))
      @post_builders = Array(opts.fetch(:post_builders, []))
      @converter = DefaultConverter.new(@logger, opts)
      @adoc_ext = opts.fetch(:adoc_extensions, nil)
    end

    # abort_on_exc:: if true, an exception lower down the chain will
    # abort the conversion and raised to the caller. If false, exceptions
    # will be swallowed. In both cases, an 'error' log entry is created.
    def run(abort_on_exc: true)
      TreeConverter.register_adoc_extensions(@adoc_ext)
      pre_build(abort_on_exc: abort_on_exc)
      build(abort_on_exc: abort_on_exc)
      post_build(abort_on_exc: abort_on_exc)
    ensure
      TreeConverter.unregister_adoc_extenstions
    end

    def pre_build(abort_on_exc: true)
      @pre_builders.each do |pb|
        pb.on_prebuild(@src_tree, @dst_tree, @converter)
      rescue => ex
        @logger&.error { ex.message.to_s }
        raise ex if abort_on_exc
      end
    end

    def build(abort_on_exc: true)
      @src_tree.traverse_preorder do |level, n|
        next unless n.leaf?

        # create the destination node, using the correct suffix depending on conversion backend
        rel_path = n.relative_path_from(@src_tree)
        Giblog.logger.debug { "Creating dst node: #{rel_path}" }
        dst_node = @dst_tree.add_descendants(rel_path)

        # perform the conversion
        @converter.convert(n, dst_node, @dst_tree)
      rescue => exc
        @logger&.error { "#{n.pathname} - #{exc.message}" }
        raise exc if abort_on_exc
      end
    end

    def post_build(abort_on_exc: true)
      @post_builders.each do |pb|
        pb.on_postbuild(@src_tree, @dst_tree, @converter)
      rescue => exc
        raise exc if abort_on_exc
        @logger&.error { exc.message.to_s }
      end
    end

    # the default callback will tie a 'SuccessfulConversion' instance
    # to the destination node as its data
    def self.on_success(src_node, dst_node, dst_tree, doc, adoc_log_str)
      dst_node.data = DataDelegator.new(SuccessfulConversion.new(
        src_node: src_node, dst_node: dst_node, dst_top: dst_tree, adoc: doc, adoc_stderr: adoc_log_str
      ))
    end

    # the default callback will tie a 'FailedConversion' instance
    # to the destination node as its data
    def self.on_failure(src_node, dst_node, dst_tree, ex, adoc_log_str)
      Giblog.logger.error { ex.message }
      dst_node.data = DataDelegator.new(FailedConversion.new(
        src_node: src_node, dst_node: dst_node, dst_top: dst_tree, error_msg: ex.message
      ))
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
      api_opts.merge!(src_node.api_options(src_node, dst_node, dst_top)) if src_node.respond_to?(:api_options)
      api_opts[:attributes].merge!(src_node.document_attributes(src_node, dst_node, dst_top)) if src_node.respond_to?(:document_attributes)

      # use a new logger instance for each conversion
      adoc_logger = Giblish::AsciidoctorLogger.new(@adoc_log_level)

      begin
        # load the source and parse it to enable access to doc
        # properties
        # NOTE: the 'parse: false' is needed to prevent preprocessor extensions to be run as part
        # of loading the document. We want them to run during the 'convert' call later when
        # doc attribs have been amended.
        doc = Asciidoctor.load(src_node.adoc_source(src_node, dst_node, dst_top), api_opts.merge(
          {
            parse: false,
            logger: adoc_logger
          }
        ))

        # piggy-back our own info on the doc attributes hash so that
        # asciidoctor extensions can use this info later on
        doc.attributes["giblish-info"] = {
          src_node: src_node,
          dst_node: dst_node,
          dst_top: dst_top
        }

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
        @logger&.error { "Conversion failed for #{src_node.pathname}" }
        @logger&.error { ex.message }
        @logger&.error { ex.backtrace }
        @conv_cb[:failure]&.call(src_node, dst_node, dst_top, ex, adoc_logger.in_mem_storage.string)
        false
      end
    end
  end
end
