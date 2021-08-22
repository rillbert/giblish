module Giblish
  class DocAttributesBase
    def document_attributes(src_node, dst_node, dst)
      raise NotImplementedError
    end
  end

  class AbsoluteCssDocAttr < DocAttributesBase
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
    def initialize(css_path)
      @css_path = Pathname.new(css_path)
      @rel_path = nil
    end

    def document_attributes(src_node, dst_node, dst_top)
      rel_path = @css_path.relative_path_from(dst_node.pathname.dirname)
      {
        "stylesdir" => rel_path.dirname.to_s,
        "stylesheet" => rel_path.basename.to_s,
        "linkcss" => true,
        "copycss" => nil
      }
    end
  end

  class PdfCustomStyle < DocAttributesBase
    def initialize(pdf_style_path, pdf_font_dirs = nil)
      @pdf_style_path = pdf_style_path
      # one can specify multiple font dirs as:
      # -a pdf-fontsdir="path/to/fonts;path/to/more-fonts"
      @pdf_fontsdir = pdf_font_dirs&.collect {|d| d.to_s }&.join(';')
    end

    def document_attributes(src_node, dst_node, dst_top)
      result = {
        "pdf-style" => @pdf_style_path.basename.to_s,
        "pdf-stylesdir" => @pdf_style_path.dirname.to_s,
        "icons" => "font"
      }
      result["pdf-fontsdir"] = '"' + @pdf_fontsdir + '"' unless @pdf_fontsdir.nil?
      result
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

  class DataDelegator
    def initialize(*delegate_arr)
      @delegates = Array(delegate_arr)
    end

    def add(delegate)
      @delegates << []
    end

    def method_missing(m, *args, &block)
      d = @delegates.find do |d|
        d.respond_to?(m) 
      end

      if d.nil?
        super
      else
        d.send(m, *args, &block) unless d.nil?
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      ok = @delegates.find {
        |d| d.respond_to?(method_name)
      }

      ok || super(method_name, include_private)
    end
  end
end
