# frozen_string_literal: true

require "pathname"
require "set"

# Provides a tree structure where each node is the basename of either
# a directory or a file. A node can contain an associated 'data' object.
#
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
  attr_writer :parent

  def initialize(tail = nil, data = nil, parent = nil)
    @children = []
    @parent = parent
    @name = nil
    return if tail.nil?

    tail = tail.split("/") unless tail.is_a?(Array)

    @name = tail.empty? ? "" : tail.shift
    if tail.length.positive?
      @children << PathTree.new(tail, data, self)
    else
      @data = data
    end
  end

  # return:: a Pathname with the full path of this node (starting from 
  # the root)
  def pathname
    return Pathname.new(@name.to_s.empty? ? "/#{@name}" : @name.to_s) if @parent.nil?

    @parent.pathname / name
  end

  # adds a new path to the tree and associates the data
  # to the leaf of that path.
  def add_path(path, data = nil)
    raise ArgumentError, "Trying to add already existing path" unless node(path).nil?

    # prune any part of the given path that already exists in this
    # tree
    p = Pathname.new(path)
    p.ascend do |q| 
      n = node(q)
      next if n.nil?

      t = PathTree.new(p.relative_path_from(q).to_s, data)
      n.append_tree(t)
      return self
    end

    # no part of the given path existed within the tree
    raise ArgumentError, "Trying to add path with other root is not supported"
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

  # returns:: the number of nodes in the subtree with this node as
  # root
  def count
    result = 1
    traverse_preorder do |level, node|
      result += 1
    end
    result
  end

  # return:: true if the node is a leaf, false otherwise
  def leaf?
    @children.length.zero?
  end

  # return:: an array with Pathnames of each full
  # path for the leaves in this tree
  def leave_pathnames
    paths = []
    traverse_postorder do |l,n| 
      paths << n.pathname if n.leaf?
    end
    paths
  end

  # return:: true if this node does not have a parent
  def root?
    @parent.nil?
  end

  # path:: the full path to an existing node in this tree (string or Pathname)
  #
  # return:: the node with the given path or nil if the path
  # does not exist within this pathtree
  def node(path)
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


  # adds a copy of the given Pathtree as a subtree to this node. the subtree can not
  # contain nodes that will end up having the same pathname as any existing
  # node in the target tree.
  # 
  # == Example
  # 
  # 1. Add my/new/tree to /1/2 -> /1/2/my/new/tree
  # 2. Add /my/new/tree to /1/2 -> /1/2//my/new/tree (where a node with empty
  # name is located between node '2' and 'my')
  # 2. Trying to add 'new/tree' to '/my' node in a tree with '/my/new/tree' raises
  # ArgumentError since the pathname that would result already exists within the 
  # target tree.
  def append_tree(root_node)

    # make a copy to make sure it is a self-sustaining PathTree
    c = root_node.dup

    # get all leaf paths prepended with this node's name to check for
    # previous existance in this tree.
    p = c.leave_pathnames.collect { |p| Pathname.new(self.name) / p }

    # duplicate ourselves to compare paths
    t = self.dup

    # check that no path in c would collide with existing paths
    common = Set.new(t.leave_pathnames) & Set.new(p)
    unless common.empty?
      str = common.collect {|p| p.to_s}.join(',')
      raise ArgumentError, "Can not append tree due to conflicting paths: #{str}"
    end

    # hook the subtree into this tree
    @children << c
    c.parent = self
  end


  # duplicate this node and all its children but keep the same data references
  # as the originial nodes.
  # 
  # parent:: the parent node of the copy, default = nil (the copy
  # is a root node)
  # returns:: a copy of this node and all its descendents. The copy will
  # share any 'data' references with the original.
  def dup(parent: nil)
    d = PathTree.new(@name.dup, @data, parent)

    @children.each { |c| d.children << c.dup(parent: d) }
    d
  end

  # Builds a PathTree with its root as the given file system dir or file
  #
  # fs_point:: an absolute or relative path to a file or directory that
  # already exists in the file system.
  # prune:: if true, add the entire, absolute, path to the fs_point to
  # the PathTree. If false, use only the basename of the fs_point as the
  # root of the PathTree
  #
  # You can submit a filter predicate that determine if a specific path
  # shall be part of the PathTree or not ->(Pathname) { return true/false}
  #
  # return:: the resulting PathTree
  #
  # === Example
  #
  # Build a pathtree containing all files under the "mydir" directory that
  # ends with '.jpg'. The resulting tree will contain the absolute path
  # to 'mydir' as nodes (eg '/home/gunnar/mydir')
  #
  # t = PathTree.build_from_fs("./mydir",true ) { |p| p.extname == ".jpg" }
  def self.build_from_fs(fs_point, prune: false)
    p = Pathname.new(fs_point)
    raise ArgumentError, "The path '#{fs_point}' does not exist in the file system!" unless p.exist?

    p = p.realpath

    t = nil
    Find.find(p.to_s) do |path|
      if t.nil?
        puts "init with path: #{path}"
        t = PathTree.new(path)
      else
        puts "add: #{path}"
        t.add_path(path) if (block_given? && yield(dst)) || !block_given?
      end
    end

    # newroot = t.node(p.to_s)
    # puts newroot.pathname
    # k = newroot.dup
    # puts k.pathname

    (prune ? t.node(p.to_s).dup : t)
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
