# frozen_string_literal: true

require "pathname"

# Provides a tree structure where each node is the basename of either
# a directory or a file. A node can contain an associated 'data' object.
#
# The following paths:
# basedir/file_1
# basedir/file_2
# basedir/dir1/file_3
# basedir/dir1/file_4
# basedir/dir2/dir3/file_5
#
# are thus represented by the following path tree:
#
# basedir
#   file_1
#   file_2
#   dir1
#     file_3
#     file_4
#   dir2
#     dir3
#       file_5
#
# == Tree info
# see https://www.geeksforgeeks.org/tree-traversals-inorder-preorder-and-postorder/
#
class PathTree
  attr_reader :name, :data, :children, :parent

  def initialize(tail = nil, data = nil, parent = nil)
    @children = []
    @parent = parent
    @name = nil
    return if tail.nil?

    tail = tail.split("/") unless tail.is_a?(Array)
    @name = tail.shift
    if tail.length.positive?
      @children << PathTree.new(tail, data, self)
    else
      @data = data
    end
  end

  # return:: a Pathname with the full path of this node
  def pathname
    return Pathname.new(name.to_s) if @parent.nil?

    @parent.pathname / name
  end

  # adds a new path to the tree and associates the data
  # to the leaf of that path.
  def add_path(tail, data = nil)
    tail = tail.split("/") unless tail.is_a?(Array)
    return if tail.empty?

    name = tail.shift
    raise ArgumentError, "Trying to add path with other root is not supported" if name != @name
    raise ArgumentError, "Trying to add already existing path" if tail.empty?

    new_name = tail[0]
    ch = get_child(new_name)
    unless ch
      new_data = tail.length == 1 ? data : nil
      ch = PathTree.new(new_name, new_data, self)
      @children << ch
      return self if tail.length == 1
    end

    ch.add_path(tail, data)
    self
  end

  # Visits depth-first by root -> left -> right
  #
  # level:: the number of hops from the root node
  # block:: the user supplied block that is executed for every visited node
  #
  # the level and node are given as block parameters
  #
  # === Examples
  # Print the name of each node together with the level of the node
  #    traverse_preorder{ |level, n| puts "#{level} #{n.name}" }
  #
  def traverse_preorder(level = 0, &block)
    yield(level, self)
    @children.each do |c|
      c.traverse_preorder(level + 1, &block)
    end
  end

  # Visits depth-first by left -> right -> root
  #
  # level:: the number of hops from the root node
  # block:: the user supplied block that is executed for every visited node
  #
  # the level and node are given as block parameters
  #
  # === Examples
  # Print the name of each node together with the level of the node
  #    traverse_postorder{ |level, n| puts "#{level} #{n.name}" }
  #
  def traverse_postorder(level = 0, &block)
    @children.each do |c|
      c.traverse_postorder(level + 1, &block)
    end
    yield(level, self)
  end

  # Visits bredth-first left -> right for each level top-down
  #
  # level:: the number of hops from the root node
  # block:: the user supplied block that is executed for every visited node
  #
  # the level and node are given as block parameters
  #
  # === Examples
  # Print the name of each node together with the level of the node
  #    traverse_levelorder { |level, n| puts "#{level} #{n.name}" }
  #
  def traverse_levelorder(level = 0, &block)
    yield(level, self) if level == 0

    @children.each do |c|
      yield(level + 1, c)
    end
    @children.each do |c|
      c.traverse_levelorder(level + 1, &block)
    end
  end

  # Sort the nodes on each level in the tree in lexical order but put
  # leafs before non-leafs.
  def sort_leaf_first
    @children.sort! { |a, b| leaf_first(a, b) }
    @children.each(&:sort_leaf_first)
  end

  # return:: true if the node is a leaf, false otherwise
  def leaf?
    @children.length.zero?
  end

  # path:: the full path to an existing node in this tree (string or Pathname)
  #
  # return:: the subtree with the matching node as root or nil if the given path
  # does not exist within this pathtree
  def subtree(path)
    root = nil
    p = Pathname.new(path)
    traverse_preorder do |level, node|
      if node.pathname == p
        root = node
        break
      end
    end
    root
  end

  # adds the given Pathtree as a subtree to this node
  def add_tree(path_tree)
    ch = get_child(path_tree.name)
    raise ArgumentError, "Can not add subtree with same name as existing nodes!" unless ch.nil?

    @children << path_tree
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
    basedir/subdir/dir11
    basedir/subdir/dir12
    basedir/subdir/dir13
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
  layout_tree = PathTree.new
  root.traverse_postorder do |_level, node|
    sz = node.leaf? ? 1 : node.children.count
    puts "pathname: #{node.pathname}"
    puts "nof children for dir: #{node.children.count}" unless node.leaf?
    layout_tree.add_path(node.pathname.to_s, sz)
  end

  layout_tree.traverse_preorder do |level, node|
    data = node.data.nil? ? "" : node.data.to_s
    puts "#{" " * level} - #{node.pathname} #{data}"
  end
end
