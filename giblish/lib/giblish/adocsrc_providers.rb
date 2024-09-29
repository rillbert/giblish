module Giblish
  class AdocSrcItf
    def adoc_source(src_node, dst_node, dst_top)
      raise NotImplementedError
    end
  end

  class SrcFromFile < AdocSrcItf
    def adoc_source(src_node, dst_node, dst_top)
      File.read(src_node.pathname)
    end
  end

  class SrcFromString < AdocSrcItf
    def initialize(src_str)
      @adoc_source = src_str
    end

    def adoc_source(src_node, dst_node, dst_top)
      @adoc_source
    end
  end
end
