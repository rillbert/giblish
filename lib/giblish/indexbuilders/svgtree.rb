# frozen_string_literal: true

module SvgSerialize
  def to_s
    attr = self.class.instance_methods.grep(/[a-z_]+=/).map { |m| m.to_s.gsub(/^(.+)=$/, '\1') }
    attr.map do |a|
      %(#{a}="#{eval(a)}") unless eval(a).nil?
    end.join(" ")
  end
end

module Giblish
  class SvgPoint
    include SvgSerialize
    attr_accessor :x, :y
  end

  class SvgArea
    include SvgSerialize
    attr_accessor :width, :height
  end

  # Generate asciidoc that represents a given pathtree as an
  # svg image
  class SvgTree
    # options:
    # dir_index_base_name: String - the basename of the index file
    # residing in each directory
    def initialize(tree, options)
      @tree = tree
      @nof_missing_titles = 0
      @options = options.dup
      @view_box = "0 0 1200 800"
    end

    def source
      tree_string = +header
      # generate each tree entry string
      @tree.traverse_post_order do |level, node|
        file_svg if node.leaf?
        tree_string << tree_entry_string(level, node)
      end

      # generate the tree footer
      tree_string << "\n----\n"
    end

    private

    def create_layout(path_tree)
      layout_tree = PathTree.new
      path_tree.traverse_post_order do |_level, node|
        sz = node.leaf? ? 1 : node.children.count
        layout_tree.add_path(node.pathname, sz)
      end
    end

    def header
      <<~SVG_HEADER
        <svg viewBox="#{@view_box}" xmlns="http://www.w3.org/2000/svg">
      SVG_HEADER
    end

    def footer
      "</svg>"
    end

    def file_svg(upper_left_coord, rect)
      %(<rect #{upper_left_coord} #{rect} />)
    end

    def dir_svg(upper_left_coord, rect)
      %(<rect #{upper_left_coord} #{rect} />)
    end
  end
end
