require "pathname"
require "set"

#
# Provides a tree structure where each node is the basename of either
# a directory or a file. The pathname of a node is the concatenation of
# all basenames from the root node to the node in question, given as a
# Pathname object.
#
# Each node must have a unique pathname within the tree it is part of.
#
# A node can contain an associated 'data' object.
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
  attr_reader :data, :name, :children, :parent, :abs_root
  attr_writer :parent, :data

  def initialize(path, data = nil, parent = nil)
    p = clean(path)
    raise ArgumentError, "Can not instantiate node with path == '.'" if p.to_s == "."
    raise ArgumentError, "Trying to create a non-root node using an absolute path" if p.absolute? && !parent.nil?

    head = p.descend.first

    @name = head
    @children = []
    @parent = parent

    tail = p.relative_path_from(head)
    if tail.to_s == "."
      @data = data
      return
    end

    add_descendants(tail, data)
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

  def name=(name)
    name = Pathname.new(name)
    
    if !parent.nil? && @parent.children.any? {|c| c.name == name }
      raise ArgumentError,"Can not rename to #{name}. An existing node already use that name" 
    end

    @name = name
  end

  # return:: a String with the path segment for this node
  def segment
    @name.to_s
  end

  # return:: a Pathname with the complete path from the root of the
  # tree where this node is a member to this node (inclusive).
  def pathname
    return @name if @parent.nil?

    (@parent.pathname / @name).cleanpath
  end

  # create a subtree from the given path and add it to this node
  #
  # return:: the leaf node for the added subtree
  def add_descendants(path, data = nil)
    p = clean(path)
    raise ArgumentError, "Can not add absolute path as descendant!!" if p.absolute?

    # invoked with 'current' name, ignore
    return self if p.to_s == "."

    head = p.descend.first
    tail = p.relative_path_from(head)
    last_segment = tail.to_s == "."

    ch = get_child(head)
    if ch.nil?
      @children << PathTree.new(head, last_segment ? data : nil, self)
      ch = @children.last
    end

    last_segment ? @children.last : ch.add_descendants(tail, data)
  end

  # adds a new path to the root of the tree where this node is a member
  # and associates the given data to the leaf of that path.
  def add_path(path, data = nil)
    p = clean(path)
    raise ArgumentError, "Trying to add already existing path: #{path}" unless node(p, from_root: true).nil?

    # prune any part of the given path that already exists in this
    # tree
    p.ascend do |q|
      n = node(q, from_root: true)
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
  # === Returns
  # A new array containing the values returned by the block
  #
  # === Examples
  # Print the name of each node together with the level of the node
  #    traverse_preorder{ |level, n| puts "#{level} #{n.segment}" }
  #
  def traverse_preorder(level = 0, &block)
    result = Array[yield(level, self)]
    @children.each do |c|
      result.append(*c.traverse_preorder(level + 1, &block))
    end
    result
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
  #    traverse_postorder{ |level, n| puts "#{level} #{n.segment}" }
  #
  def traverse_postorder(level = 0, &block)
    result = []
    @children.each do |c|
      result.concat(c.traverse_postorder(level + 1, &block))
    end
    result << yield(level, self)
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
  #    traverse_levelorder { |level, n| puts "#{level} #{n.segment}" }
  #
  def traverse_levelorder(level = 0, &block)
    result = []
    # the node of the original call
    result << yield(level, self) if level == 0

    # this level
    @children.each do |c|
      result << yield(level + 1, c)
    end

    # next level
    @children.each do |c|
      result.concat(c.traverse_levelorder(level + 1, &block))
    end

    result
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
    result = 0
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
  def leave_pathnames(prune: false)
    paths = []
    traverse_postorder do |l, n|
      next unless n.leaf?

      paths << (prune ? n.pathname.relative_path_from(self.pathname) : n.pathname)
    end
    paths
  end

  # return:: true if this node does not have a parent node
  def root?
    @parent.nil?
  end

  # return:: the root node of the tree where this node is a member
  def root
    return self if root?

    @parent.root
  end

  # Finds the node corresponding to the given path.
  # 
  # path:: a String or Pathname with the path to search for
  # from_root:: if true start the search from the root of the tree where 
  # this node is a member. If false, start the search from this node's 
  # children.
  #
  # return:: the node with the given path or nil if the path
  # does not exist within this pathtree
  def node(path, from_root: false)
    p = clean(path)
    root = nil

    traverse_preorder do |level, node|
      q = from_root ? node.pathname : node.pathname.relative_path_from(pathname)
      if q == p
        root = node
        break
      end
    end
    root
  end

  # adds a copy of the given Pathtree as a subtree to this node. the subtree can not
  # contain nodes that will end up having the same pathname as any existing
  # node in the target tree. Note that 'data' attributes will not be copied. The copied
  # Pathtree nodes will thus point to the same data attributes as the original.
  #
  # == Example
  #
  # 1. Add my/new/tree to /1/2 -> /1/2/my/new/tree
  # 2. Add /my/new/tree to /1/2 -> ArgumentError - can not add root as subtree
  # 3. Trying to add 'new/tree' to '/my' node in a tree with '/my/new/tree' raises
  # ArgumentError since the pathname that would result already exists within the
  # target tree.
  def append_tree(root_node)
    raise ArgumentError, "Trying to append a root node as subtree!" if root_node.pathname.root?

    # make a copy to make sure it is a self-sustaining PathTree
    c = root_node.dup

    # get all leaf paths prepended with this node's name to check for
    # previous existance in this tree.
    p = c.leave_pathnames.collect { |p| Pathname.new(@name) / p }

    # duplicate ourselves to compare paths
    t = dup

    # check that no path in c would collide with existing paths
    common = Set.new(t.leave_pathnames) & Set.new(p)
    unless common.empty?
      str = common.collect { |p| p.to_s }.join(",")
      raise ArgumentError, "Can not append tree due to conflicting paths: #{str}"
    end

    # hook the subtree into this tree
    @children << c
    c.parent = self
  end

  # Splits the node's path into
  # - a 'stem', the common path to all nodes in this tree that are on the
  # same level as this node or closer to the root.
  # - a 'crown', the remaining path when the stem has been removed from this
  # node's pathname
  #
  # === Example
  # n.split_stem for the following tree:
  #
  #   base
  #     |- dir
  #         |- leaf_1
  #         |- branch
  #               |- leaf_2
  #
  # yields
  #        ["base/dir", "leaf_1"] when n == leaf_1
  #        ["base/dir", "branch/leaf_2"] when n == leaf_2
  #        ["base", "dir"] when n == "dir"
  #        [nil, "base"] when n == "base"
  #
  # return:: [stem, crown]
  def split_stem
    r = root
    s = pathname.descend do |stem|
      n = r.node(stem, from_root: true)
      break n if n.children.count != 1 || n == self
    end

    if s == self
      [root? ? nil : s.parent.pathname, @name]
    else
      [s.pathname, pathname.relative_path_from(s.pathname)]
    end
  end

  # return:: a Pathname containing the relative path to this node as seen from the
  # given node
  def relative_path_from(node)
    pathname.relative_path_from(node.pathname)
  end

  # Builds a PathTree with its root as the given file system dir or file
  #
  # fs_point:: an absolute or relative path to a file or directory that
  # already exists in the file system.
  # prune:: if false, add the entire, absolute, path to the fs_point to
  # the PathTree. If true, use only the basename of the fs_point as the
  # root of the PathTree
  #
  # You can submit a filter predicate that determine if a specific path
  # shall be part of the PathTree or not ->(Pathname) { return true/false}
  #
  # return:: the node corresponding to the given fs_point in the resulting
  # pathtree or nil if no nodes matched the given predicate filter
  #
  # === Example
  #
  # Build a pathtree containing all files under the "mydir" directory that
  # ends with '.jpg'. The resulting tree will contain the absolute path
  # to 'mydir' as nodes (eg '/home/gunnar/mydir')
  #
  # t = PathTree.build_from_fs("./mydir",true ) { |p| p.extname == ".jpg" }
  def self.build_from_fs(fs_point, prune: false)
    top_node = Pathname.new(fs_point).cleanpath
    raise ArgumentError, "The path '#{fs_point}' does not exist in the file system!" unless top_node.exist?

    top_node = top_node.realpath

    t = nil
    Find.find(top_node.to_s) do |path|
      p = Pathname.new(path)

      if (block_given? && yield(p)) || !block_given?
        t.nil? ? t = PathTree.new(p) : t.add_path(p)
      end
    end
    return nil if t.nil?

    # always return the entry node but prune the parents if
    # users wishes
    entry_node = t.node(top_node, from_root: true)
    (prune ? entry_node.dup : entry_node)
  end

  # delegate method calls not implemented by PathTree to the associated 'data'
  # object
  def method_missing(m, *args, &block)
    return super if data.nil?

    data.send(m, *args, &block)
  end

  def respond_to_missing?(method_name, include_private = false)
    return super(method_name,include_private) if data.nil?
    
    data.respond_to?(method_name)
  end

  def to_s
    traverse_preorder do |level, n|
       str = " "*4*level + "|-- " + n.segment.to_s
       str += " <#{n.data}>" unless n.data.nil?
       str
    end.join("\n")
  end

  # Return a new PathTree with the nodes whith pathname matching the 
  # given regex.
  # 
  # The copy will point to the same node data as the original.
  #
  # regex:: a Regex matching the pathname of the nodes to be included in
  # the copy
  # prune:: remove all parents to this node in the returned copy
  # 
  # === Returns
  # the entry node in a new PathTree with the nodes with pathnames matching the given regex
  # or nil if no nodes match
  def match(regex, prune: false)
    copy = nil
  
    traverse_preorder do |level, n|
      p = n.pathname
      next unless regex =~ p.to_s

      copy.nil? ? copy = PathTree.new(p,n.data) : copy.add_path(p, n.data)
    end
    return nil if copy.nil?

    # always return the entry node but return a pruned version if
    # the user wishes
    entry_node = copy.node(self.pathname, from_root: true)
    (prune ? entry_node.dup : entry_node)
  end

  # Return a new PathTree with the nodes matching the given block
  # 
  # The copy will point to the same node data as the original.
  #
  # prune:: prune all parents to this node from the returned copy
  #
  # === Block 
  # 
  # The given block will receive the level (from the entry node) and
  # the node itself for each node.
  # 
  # === Returns
  # the entry node to the new Pathtree or nil if no nodes matched the
  # given block.
  #
  # === Example
  # 
  #   copy = original.filter { |l, n| n.data == "smurf" }
  # 
  # The above will return a tree with nodes whose data is equal to 'smurf'
  def filter(prune: false)
    raise InvalidArgument, "No block given!" unless block_given?

    # build the filtered copy
    copy = nil  
    traverse_preorder do |level, n|
      if (yield(level,n))
        p = n.pathname
        copy.nil? ? copy = PathTree.new(p,n.data) : copy.add_path(p, n.data)
      end
    end

    return nil if copy.nil?

    # always return the entry node but return a pruned version if
    # the user wishes
    entry_node = copy.node(self.pathname, from_root: true)
    (prune ? entry_node.dup : entry_node)
  end

  private

  def clean(path)
    Pathname.new(path).cleanpath
  end

  def leaf_first(left, right)
    if left.leaf? != right.leaf?
      # always return leaf before non-leaf
      return left.leaf? ? -1 : 1
    end

    # for two non-leafs, return lexical order
    left.segment <=> right.segment
  end

  def get_child(segment_name)
    ch = @children.select { |c| c.segment == segment_name.to_s }
    ch.length.zero? ? nil : ch[0]
  end
end
