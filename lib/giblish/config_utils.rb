module Giblish
  # delegates all method calls to the first supplied delegate that
  # implements it.
  class DataDelegator
    def initialize(*delegate_arr)
      @delegates = Array(delegate_arr)
    end

    def add(delegate)
      @delegates << delegate
    end

    def method_missing(m, *args, &block)
      d = @delegates.find { |d| d.respond_to?(m) }
      d.nil? ? super : d&.send(m, *args, &block)
    end

    def respond_to_missing?(method_name, include_private = false)
      ok = @delegates.find { |d|
        d.respond_to?(method_name)
      }

      ok || super(method_name, include_private)
    end
  end
end
