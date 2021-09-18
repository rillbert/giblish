module Giblish
  class DocAttributesBase
    def document_attributes(src_node, dst_node, dst)
      raise NotImplementedError
    end
  end

  class AbsoluteLinkedCss < DocAttributesBase
    def initialize(css_path)
      @css_path = Pathname.new(css_path)
    end

    def document_attributes(src_node, dst_node, dst_top)
      {
        "stylesdir" => @css_path.dirname.to_s,
        "stylesheet" => @css_path.basename.to_s,
        "linkcss" => true,
        "copycss" => nil
      }
    end
  end

  class RelativeCssDocAttr < DocAttributesBase
    # dst_css_path_rel:: the relative path to the dst top to the location of the
    # css file to use
    def initialize(dst_css_path_rel)
      @css_path = Pathname.new(dst_css_path_rel)
    end

    def document_attributes(src_node, dst_node, dst_top)
      href_path = dst_top.relative_path_from(dst_node).dirname / @css_path
      {
        "stylesdir" => href_path.dirname.to_s,
        "stylesheet" => href_path.basename.to_s,
        "linkcss" => true,
        "copycss" => nil
      }
    end
  end

  class PdfCustomStyle < DocAttributesBase
    # pdf_style_path:: the path name (preferable absolute) to the yml file
    # pdf_font_dirs:: one or more Pathnames to each font dir that shall be
    # checked for fonts
    def initialize(pdf_style_path, *pdf_font_dirs)
      @pdf_style_path = pdf_style_path
      # one can specify multiple font dirs as:
      # -a pdf-fontsdir="path/to/fonts;path/to/more-fonts"
      # Always use the GEM_FONTS_DIR token to load the adoc-pdf gem's font dirs as well
      @pdf_fontsdir = (Array(pdf_font_dirs) << "GEM_FONTS_DIR").collect { |d| d.to_s }&.join(";")
    end

    def document_attributes(src_node, dst_node, dst_top)
      result = {
        "pdf-style" => @pdf_style_path.basename.to_s,
        "pdf-stylesdir" => @pdf_style_path.dirname.to_s,
        "icons" => "font"
      }
      result["pdf-fontsdir"] = @pdf_fontsdir unless @pdf_fontsdir.nil?
      result
    end
  end

  # provides the default, opinionated doc attributes used
  # when nothing else is set
  class GiblishDefaultDocAttribs
    def document_attributes(src_node, dst_node, dst_top)
      {
        "source-highlighter" => "rouge",
        "xrefstyle" => "short"
      }
    end
  end

  class CmdLineDocAttribs
    def initialize(cmd_opts)
      @cmdline_attrs = cmd_opts.doc_attributes.dup
    end

    def document_attributes(src_node, dst_node, dst_top)
      @cmdline_attrs
    end
  end

  # a builder class that can be setup with one or more document
  # attribute providers and then used as the sole doc attrib provider
  # where the merged sum of all added providers will be presented.
  #
  # If more than one added provider set the same doc attrib, the last
  # added has preference.
  #
  # Each added provider must conform to the itf defined in
  # the DocAttributesBase class.
  class DocAttrBuilder
    attr_reader :providers

    def initialize(*attr_providers)
      @providers = []
      add_doc_attr_providers(*attr_providers)
    end

    def add_doc_attr_providers(*attr_providers)
      return if attr_providers.empty?

      # check itf compliance of added providers
      attr_providers.each do |ap|
        unless ap.respond_to?(:document_attributes) &&
            ap.method(:document_attributes).arity == 3
          raise ArgumentError, "The supplied doc attribute provider of type: #{ap.class} did not conform to the interface"
        end
      end

      @providers += attr_providers
    end

    def document_attributes(src_node, dst_node, dst_top)
      result = {}
      @providers.each { |p| result.merge!(p.document_attributes(src_node, dst_node, dst_top)) }
      result
    end
  end
end
