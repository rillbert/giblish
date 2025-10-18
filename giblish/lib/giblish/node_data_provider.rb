module Giblish
  # Provides a unified interface for node data by explicitly composing
  # multiple providers into a single object.
  #
  # Supports dynamic composition - providers can be added after initialization.
  # Each method explicitly delegates to the first provider that responds to it.
  class NodeDataProvider
    def initialize(*providers)
      @providers = Array(providers).compact
    end

    def add_provider(provider)
      @providers << provider
      self
    end

    # === Source Node Interface (DocAttrBuilder + AdocSrcProvider) ===

    def document_attributes(src_node, dst_node, dst_top)
      provider = find_provider(:document_attributes)
      provider.document_attributes(src_node, dst_node, dst_top)
    end

    def adoc_source(src_node, dst_node, dst_top)
      provider = find_provider(:adoc_source)
      provider.adoc_source(src_node, dst_node, dst_top)
    end

    def api_options(src_node, dst_node, dst_top)
      provider = find_provider(:api_options, raise_on_missing: false)
      return {} unless provider
      provider.api_options(src_node, dst_node, dst_top)
    end

    # === Conversion Info Interface (SuccessfulConversion / FailedConversion) ===

    def src_node
      provider = find_provider(:src_node)
      provider.src_node
    end

    def dst_node
      provider = find_provider(:dst_node)
      provider.dst_node
    end

    def dst_top
      provider = find_provider(:dst_top)
      provider.dst_top
    end

    def converted
      provider = find_provider(:converted)
      provider.converted
    end

    def src_rel_path
      provider = find_provider(:src_rel_path)
      provider.src_rel_path
    end

    def src_basename
      provider = find_provider(:src_basename)
      provider.src_basename
    end

    def title
      provider = find_provider(:title)
      provider.title
    end

    def docid
      provider = find_provider(:docid)
      provider.docid
    end

    def to_s
      provider = find_provider(:to_s)
      provider.to_s
    end

    # SuccessfulConversion specific
    def stderr
      provider = find_provider(:stderr)
      provider.stderr
    end

    def adoc
      provider = find_provider(:adoc)
      provider.adoc
    end

    def dst_rel_path
      provider = find_provider(:dst_rel_path)
      provider.dst_rel_path
    end

    def purpose_str
      provider = find_provider(:purpose_str)
      provider.purpose_str
    end

    # FailedConversion specific
    def error_msg
      provider = find_provider(:error_msg)
      provider.error_msg
    end

    # === History Interface (FileHistory) ===

    def history
      provider = find_provider(:history, raise_on_missing: false)
      return nil unless provider
      provider.history
    end

    def branch
      provider = find_provider(:branch, raise_on_missing: false)
      return nil unless provider
      provider.branch
    end

    def respond_to?(method_name, include_private = false)
      find_provider(method_name, raise_on_missing: false) ? true : super
    end

    private

    def find_provider(method_name, raise_on_missing: true)
      provider = @providers.find { |p| p.respond_to?(method_name) }
      if provider.nil? && raise_on_missing
        raise NoMethodError, "None of the providers respond to '#{method_name}'"
      end
      provider
    end
  end
end
