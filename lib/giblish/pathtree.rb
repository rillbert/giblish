# frozen_string_literal: true

# This class can convert the following paths:
# basedir/file_1
# basedir/file_2
# basedir/dir1/file_3
# basedir/dir1/file_4
# basedir2/dir2/dir3/file_5
#
# into the following tree:
# basedir
#   file_1
#   file_2
#   dir1
#     file_3
#     file_4
# basedir2
#   dir2
#     dir3
#       file_5
class PathTree
  attr_reader :name, :data

  def initialize(tail = nil, data = nil)
    @children = []
    @name = nil
    return unless tail

    tail = tail.split("/") unless tail.is_a?(Array)
    @name = tail.shift
    if tail.length.positive?
      @children << PathTree.new(tail, data)
    else
      @data = data
    end
  end

  # adds a new path to the tree and associates the data 
  # to the leaf of that path.
  def add_path(tail, data = nil)
    tail = tail.split("/") unless tail.is_a?(Array)
    return if tail.empty?

    ch = get_child tail[0]
    if ch
      tail.shift
      ch.add_path tail, data
    else
      @children << PathTree.new(tail, data)
    end
  end

  # Public: Visits each node by following each branch down from the
  #         root, one at the time.
  #
  # level - the number of hops from the root node
  # block - the user supplied block that is executed for every visited node
  #         the level and node are given as block parameters
  #
  # Examples
  # Print the name of each node together with the level of the node
  # traverse_top_down{ |level, n| puts "#{level} #{n.name}" }
  def traverse_top_down(level = 0, &block)
    @children.each do |c|
      yield(level, c)
      c.traverse_top_down(level + 1, &block)
    end
  end

  # Public: Sort the nodes on each level in the tree in lexical order but put
  # leafs before non-leafs.
  def sort_leaf_first
    # sort on this level
    @children.sort! { |a, b| leaf_first(a, b) }
    # sort each subtree
    @children.each(&:sort_leaf_first)
  end

  # Public: is this node a leaf
  #
  # Returns: true if the node is a leaf, false otherwise
  def leaf?
    @children.length.zero?
  end

  private

  def leaf_first(left, right)
    if left.leaf? != right.leaf?
      # always return leaf before non-leaf
      return left.leaf? ? -1 : 1
    end

    # for two non-leafs, return lexical order
    left.name <=> right.name
  end

  def get_child(segment_name)
    ch = @children.select { |c| c.name == segment_name }
    ch.length.zero? ? nil : ch[0]
  end
end

# test the class...
if __FILE__ == $PROGRAM_NAME
  paths = %w[basedir/file_a
             basedir/file_a
             basedir/dira
             basedir/dira/file_c
             basedir/dirb/file_e
             basedir/dira/file_d
             basedir2/dir2/dir3/file_k
             basedir2/dir1/dir3/file_l
             basedir2/dir1/dir3/file_l
             basedir2/file_h
             basedir2/dir2/dir3/file_m]

  root = PathTree.new
  count = 0
  paths.each do |p|
    puts "adding path: #{p}"
    root.add_path p, count
    count += 1
  end
  root.sort_leaf_first
  root.traverse_top_down do |level, node|
    data = node.data.nil? ? "" : node.data.to_s
    puts "#{' ' * level} - #{node.name} #{data}"
  end
end
