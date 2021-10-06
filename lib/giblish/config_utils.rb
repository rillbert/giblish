module Giblish
  # delegates all method calls to the first supplied delegate that
  # implements it.
  class DataDelegator
    attr_reader :delegates

    def initialize(*delegate_arr)
      @delegates = Array(delegate_arr)
    end

    def add(delegate)
      @delegates << delegate
    end

    # define this to short-cut circular references
    #
    # TODO: This should probably be avoided by refactoring the SuccessfulConversion
    # class which, as of this writing, is part of a circular ref to a PathTree which
    # throws 'inspect' calls into an eternal loop instead of implementing a custom 'inspect'
    # method.
    def inspect
      @delegates.map do |d|
        "<#{d.class}:#{d.object_id}>"
      end.join(",")
    end

    def method_missing(m, *args, &block)
      del = @delegates&.find { |d| d.respond_to?(m) }

      del.nil? ? super : del.send(m, *args, &block)
    end

    def respond_to_missing?(method_name, include_private = false)
      ok = @delegates.find { |d|
        d.respond_to?(method_name)
      }

      ok || super(method_name, include_private)
    end
  end
end
