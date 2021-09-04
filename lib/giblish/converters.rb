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

  class AdocSrcBase
    def adoc_source(src_node, dst_node, dst_top)
      raise NotImplementedError
    end
  end

  class SrcFromFile < AdocSrcBase
    def adoc_source(src_node, dst_node, dst_top)
      File.read(src_node.pathname)
    end
  end

  class SrcFromString < AdocSrcBase
    def initialize(src_str)
      @adoc_source = src_str
    end

    def adoc_source(src_node, dst_node, dst_top)
      @adoc_source
    end
  end
end
