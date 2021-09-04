module Giblish
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

  # delegates all method calls to the first supplied delegate the
  # implements it.
  class DataDelegator
    def initialize(*delegate_arr)
      @delegates = Array(delegate_arr)
    end

    def add(delegate)
      @delegates << delegate
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
      ok = @delegates.find { |d|
        d.respond_to?(method_name)
      }

      ok || super(method_name, include_private)
    end
  end
end
