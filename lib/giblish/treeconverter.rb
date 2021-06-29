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
    #  pre_builders
    #  post_builders
    #  adoc_api_opts
    #  adoc_doc_attribs
    def initialize(src_top, dst_top, opts = {})
      @pre_builders = []
      @src_top = src_top
      @pre_builders = Array(opts.fetch(:pre_builders, []))
      @post_builders = Array(opts.fetch(:post_builders, []))
      @dst_tree = PathTree.new(dst_top, {})
      @dst_top = @dst_tree.node(dst_top, from_root: true)

      # merge user's options with the default, giving preference
      # to the user
      attrs = DEFAULT_ADOC_DOC_ATTRIBS.dup.merge!(
        opts.fetch(:adoc_doc_attribs, {})
      )
      @adoc_api_opts = DEFAULT_ADOC_OPTS.dup.merge!(
        opts.fetch(:adoc_api_opts, {})
      )
      @adoc_api_opts[:attributes] = attrs

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
          Asciidoctor::Extensions.register { send(e,c) }
        end
      end
    end

    
    # require the following methods to be available from the node:
    # adoc_source
    # document_attributes
    # api_options
    def convert(node, dst_tree)
      Giblog.logger.info { "Converting #{node.pathname}..." }

      # merge the common api opts with node specific
      api_opts = @adoc_api_opts.dup.merge(node.api_options)
      api_opts[:attributes].merge!(node.document_attributes)

      # load the source and parse it to enable access to doc
      # properties
      doc = Asciidoctor.load(node.adoc_source, @adoc_api_opts)

      # get dst path
      q = node.pathname.relative_path_from(@src_top.pathname).sub_ext(doc.attributes["outfilesuffix"])
      d = @dst_top.add_descendants(q).pathname

      # make sure the dir exists
      d.dirname.mkpath

      # write the converted doc to the file
      doc.attributes["giblish-src-tree-node"] = node
      output = doc.convert(@adoc_api_opts)
      doc.write(output, d.to_s)

      true
    end
  end


end
