module Giblish
  module LinkedCssAttribs
    attr_accessor :css_path
    def document_attributes
      {
        "stylesdir" => @css_path.dirname.to_s,
        "stylesheet" => @css_path.basename.to_s,
        "linkcss" => true,
        "copycss" => nil
      }
    end

    def api_options
      {
        backend: "html5"
      }
    end
  end

  module DefaultCssStyleAttribs
    def document_attributes
      {
        "linkcss" => false,
        "copycss" => true
      }
    end

    def api_options
      {
        backend: "html5"
      }
    end
  end

  module PdfCustomStyle
    attr_accessor :pdf_style_path, :pdf_fontsdir
    def document_attributes
      result = {
        "pdf-style" => @pdf_style_path.basename.to_s,
        "pdf-stylesdir" => @pdf_style_path.dirname.to_s,
        "icons" => "font"
      }
      result["pdf-fontsdir"] = @pdf_fontsdir.to_s unless @pdf_fontsdir.nil?
      result
    end

    def api_options
      {
        backend: "pdf"
      }
    end
  end

  class SrcFromFile
    def initialize(tree_node)
      @node = tree_node
    end

    def adoc_source
      File.read(@node.pathname)
    end
  end

  class SrcFromString
    attr_accessor :adoc_source
    def initialize(src_str)
      @adoc_source = src_str
    end
  end

  class HtmlLinkedCssFileSrc < SrcFromFile
    include LinkedCssAttribs

    def initialize(src_node, rel_css_path)
      super(src_node)
      @css_path = rel_css_path.cleanpath
    end
  end

  class HtmlLinkedCssStringSrc < SrcFromString
    include LinkedCssAttribs

    def initialize(src_str, rel_css_path)
      super(src_str)
      @css_path = rel_css_path.cleanpath
    end
  end

  class HtmlDefaultStyleStringSrc < SrcFromString
    include DefaultCssStyleAttribs

    def initialize(src_str)
      super(src_str)
    end
  end
end
