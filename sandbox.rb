require "erb"
require_relative "lib/giblish/pathtree"
require_relative "lib/giblish/utils"

class Shape
  attr_reader :left, :top, :width, :height

  def initialize(left=0, top=0, width=0, height=0)
    @left = left.to_f
    @top = top.to_f
    @width = width.to_f
    @height = height.to_f
  end

  def draw
    "[#{@left},#{@top}] w: #{@width} h: #{@height}"
  end

  def translate(top_left)
    @left += top_left[:left]
    @top += top_left[:top]
    self
  end
end

class TextBox < Shape
  attr_reader :lines

  # ;font-variant:normal;font-weight:normal;font-stretch:normal;font-size:5.64444447px;font-family:'Abyssinica SIL';font-variant-ligatures:normal;font-variant-caps:normal;font-variant-numeric:normal;font-feature-settings:normal;text-align:start;letter-spacing:0px;word-spacing:0px;writing-mode:lr-tb;text-anchor:start;fill:#000000;fill-opacity:1;stroke:none;stroke-width:0.26458332"
  TEXT_SVG = <<~TXT_SVG
  <text x="<%= @left %>" y="<%= @top %>"
    style="font-style:normal;font-size:<%= @font_size %>px">
    <% @lines.each_with_index do |line, i|
      y = @top + i * @font_size * 1.1 -%>
    <tspan x="<%= @left %>" y="<%= y %>"> <%= line -%> </tspan>
    <% end -%>
  </text>
  TXT_SVG

  def initialize(text_str, prefered_font_size, max_width, max_height)
    super()
    @font_size = prefered_font_size.to_f
    format_text(text_str, max_width.to_f, max_height.to_f)
  end

  def draw
    ERB.new(TEXT_SVG, trim_mode: "<>-").result(binding)
    # "  #{@lines} - font-size: #{@font_size}" + super
  end

  def width
    m = @lines.max do |l|
      l.length
    end
    m.length * @font_size
  end

  private

  def format_text(str, max_width, max_height)
    fs = @font_size
    lines = []
    height = max_height+1
    while(height > max_height)
      lines = Giblish.break_line(str, (max_width / fs).to_i)
      height = lines.count * fs * 1.1

      fs = fs * 0.8
    end
    @lines = lines
    @height = height
    @font_size = fs

    # max_chars = (str.length + max_rows) / max_rows
    # @font_size = max_width.to_f / max_chars
    # puts "s: #{str} max_chars: #{max_chars} fs: #{@font_size}"
    # Giblish.break_line(str, max_chars)
  end
end

class RoundedBox < Shape
  RECT_SVG = <<~SVG_RECT
  <rect x="<%= @left %>" y="<%= @top %>" rx="<%= @x_radii %>" ry="<%= @y_radii %>" height="<%= @height %>" width="<%= @width %>"
    style="opacity:1;fill:#d89c9b;fill-opacity:1;stroke:#000002;stroke-width:2.11666656;stroke-miterlimit:4;stroke-dasharray:none;stroke-opacity:1"
  />
  SVG_RECT

  def initialize(width, height)
    super(0,0,width, height)
    @x_radii = 5
    @y_radii = 7
  end

  def draw
    ERB.new(RECT_SVG, trim_mode: "<>-").result(binding)
  end
end

class BoxWithText < Shape
  GROUP_SVG = <<~GROUP_SVG
  <g>
  <%= @rect.draw -%>
  <%= @text.draw -%>
  </g>
  GROUP_SVG

  def initialize(text, max_width)
    super()
    @text = TextBox.new(text,5,max_width,12)
    @rect = RoundedBox.new(@text.width, @text.height)
  end

  def width
    @rect.width
  end

  def height
    @rect.height
  end

  def translate(top_left)
    @rect.translate(top_left)
    @text.translate(top_left)
    self
  end

  def draw
    ERB.new(GROUP_SVG, trim_mode: "<>-").result(binding)
  end
end

class VerticalExtendBox < Shape
  attr_reader :children

  GROUP_SVG = <<~GROUP_SVG
  <g>
    <% @children.each do |ch| -%>
    <%= ch.draw -%>
    <% end -%>
  </g>
  GROUP_SVG

  def initialize(width)
    super()
    @width = width
    @cursor = {left: 0, top: 0}
    @strip_height = 0
    @children = []
  end

  # shift the top_left in the 2d plan with the given amounts
  def translate(cursor)
    super
    @children.each do |b|
      b.translate(cursor)
    end
    self
  end

  def draw
    ERB.new(GROUP_SVG, trim_mode: "<>-").result(binding)
  end

  def height
    @cursor[:top] + @strip_height
  end

  def add(sub_shape)
    raise ArgumentError, "Too wide !!" if sub_shape.width > @width

    if free_width < sub_shape.width
      # new row
      @cursor = {left: 0, top: @cursor[:top] + @strip_height}
    end

    @children << sub_shape.translate(@cursor)

    @cursor = {left: @cursor[:left] + sub_shape.width, top: @cursor[:top]}
    @strip_height = [@strip_height, sub_shape.height].max
  end

  def free_width
    @width - @cursor[:left]
  end
end

class SvgIndex
  # viewBox="0 0 105 150"

  SVG_DATA = <<~SVG_HDR
  <svg version="1.1"
    width="80%"
    height="80%"
    viewBox="0 0 <%= @children.width -%> <%= @children.height -%>"
    xmlns="http://www.w3.org/2000/svg"
    >
  <%= @children.draw -%>
  </svg>
  SVG_HDR

  def initialize(root_object)
    @children = root_object
  end

  def draw
    ERB.new(SVG_DATA, trim_mode: "<>-").result(binding)
  end
end

def build_layout(tree, max_width)
  tree.traverse_postorder do |level, node|
    next if level == 0

    if node.parent.data.nil?
      node.parent.data = VerticalExtendBox.new(max_width)
    end
    container = node.parent.data

    child = node.leaf? ? BoxWithText.new(node.segment, max_width) : node.data
    container.add(child)
  end
  SvgIndex.new(tree.data)
end

tree = PathTree.new("root")
[
  "root/dir1/file1",
  "root/file_22",
  # "root/dir1/file_2",
  # "root/dir2/file_1",
  # "root/dir2/file_2",
  # "root/dir3/file_2",
  # "root/dir3/looooooooooong_file_2",
  "root/dir2/file_4"
].each { |p|
  tree.add_path(p)
}

shapes = build_layout(tree, 120)

File.write("test.svg", shapes.draw)
# puts shapes.draw
