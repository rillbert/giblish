# frozen_string_literal: true

module Giblish
  # heavily inspired from https://stackoverflow.com/a/746274
  class IndexBuilderRegister
    @@subclasses = {}

    # instantiate a new object of the given type
    def self.create(type,file_tree, paths)
      c = @@subclasses[type]
      raise ArgumentError, "Unknown type: #{type}" unless c

      c.new(file_tree, paths)
    end

    # dynamically register new index builder types
    def self.register(name)
      @@subclasses[name] = self
    end
  end

  # derived implementations are given as a block to this method
  def self.add_index_builder(name, superclass = BuilderBase, &block)
    c = Class.new(superclass, &block)
    c.register(name)
    Object.const_set("#{name.to_s.capitalize}BuilderBase", c)
  end
end
