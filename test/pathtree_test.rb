require "test_helper"
require "fileutils"
require_relative "../lib/giblish/pathtree"

class PathTreeTest < Minitest::Test
  include Giblish::TestUtils

  def tree_with_slash
    t = PathTree.new("/1")
    {"/1/2/4" => 124, "/1/2/5" => 125, "/1/2/6" => 126, "/1/3" => 13}.each { |p, d|
      t.add_path(p, d)
    }
    t
  end

  def tree_without_slash
    t = PathTree.new("1")
    {"1/2/4" => 124, "1/2/5" => 125, "1/2/6" => 126, "1/3" => 13}.each { |p, d|
      t.add_path(p, d)
    }
    t
  end

  def test_wrong_args_paths
    root = PathTree.new("1")
    root.add_path("1/2")

    # can not add path with differing root
    assert_raises(ArgumentError) {
      root.add_path("2")
    }

    # can not add existing path
    assert_raises(ArgumentError) {
      root.add_path("1/2")
    }
  end

  def test_whitespace_root
    t = PathTree.new(' ')
    assert_equal(0, t.children.length)
    assert_nil(t.parent)
    assert_equal(" ", t.segment)
    assert_equal(Pathname.new(" "), t.pathname)
    c = 0
    t.traverse_preorder { |level, node| c += 1 }
    t.traverse_postorder { |level, node| c += 1 }
    assert_equal(2, c)
  end

  # def test_parent_names
  #   t = PathTree.new('/hej/hopp')
  #   assert_equal(["hopp", "hej"], t.parent_names)
  # end
  def test_root_node
    t = PathTree.new("/")
    assert_equal(Pathname.new("/"),t.pathname)
    assert_equal("/",t.segment)
    assert_equal(1, t.count)

    s = PathTree.new("/1")
    assert_equal(2, s.count)
  end
  
  def test_pathname
    t = PathTree.new("/1")
    {"/1/2/4" => 124, "/1/2/5" => 125, "/1/2/6" => 126, "/1/3" => 13}.each { |p, d|
      t.add_path(p, d)
    }
    assert_equal(Pathname.new('/'), t.pathname)
    assert_equal(Pathname.new('/1/3'), t.node('/1/3').pathname)
    assert_equal(Pathname.new('/1/2'), t.node('/1/2').pathname)
    assert_equal(Pathname.new('/1/2/4'), t.node('/1/2/4').pathname)
  end

  def test_leaves
    t = tree_with_slash
    assert_equal(
      [Pathname.new("/1/2/4"), Pathname.new("/1/2/5"),
        Pathname.new("/1/2/6"), Pathname.new("/1/3")],
      t.leave_pathnames
    )

    k = t.node("/1/2")
    assert_equal(
      [Pathname.new("/1/2/4"), Pathname.new("/1/2/5"),
        Pathname.new("/1/2/6")],
      k.leave_pathnames
    )
  end

  def test_dup_with_slash
    origin = PathTree.new("/1")
    {"/1/2/4" => 124,
     "/1/2/5" => 125,
     "/1/2/6" => 126,
     "/1/3" => 13}.each { |p, d|
      origin.add_path(p, d)
    }
    copy = origin.dup
    assert(copy.object_id != origin.object_id)
    assert_equal(origin.count, copy.count)

    copy.traverse_preorder do |l, n|
      origin_node = origin.node(n.pathname)

      assert(origin_node.object_id != n.object_id)
      assert(origin_node.data.equal?(n.data)) unless origin_node.data.nil?
      assert_equal(origin_node.segment, n.segment)
      assert_equal(origin_node.data, n.data)
    end
  end

  def test_dup_without_slash
    origin = PathTree.new("1")
    {"1/2/4" => 124,
     "1/2/5" => 125,
     "1/2/6" => 126,
     "1/3" => 13}.each { |p, d|
      origin.add_path(p, d)
    }
    copy = origin.dup
    assert(copy.object_id != origin.object_id)

    copy.traverse_preorder do |l, n|
      origin_node = origin.node(n.pathname)

      assert(origin_node.object_id != n.object_id)
      assert(origin_node.data.equal?(n.data)) unless origin_node.data.nil?
      assert_equal(origin_node.segment, n.segment)
      assert_equal(origin_node.data, n.data)
    end
  end

  def test_preorder_ok
    root = PathTree.new("1")
    {"1/2/4" => 124,
     "1/2/5" => 125,
     "1/2/6" => 126,
     "1/3" => 13}.each { |p, d|
      root.add_path(p, d)
    }

    order = ""
    data = []
    level = []
    root.traverse_preorder do |l, node|
      level << l
      order << node.segment
      data << node.data
    end
    assert_equal("124563", order)
    assert_equal([0, 1, 2, 2, 2, 1], level)
    assert_equal([nil, nil, 124, 125, 126, 13], data)
  end

  def test_postorder_ok
    root = PathTree.new("1")
    {"1/2/4" => 124,
     "1/2/5" => 125,
     "1/2/6" => 126,
     "1/3" => 13}.each { |p, d|
      root.add_path(p, d)
    }

    order = ""
    data = []
    level = []
    root.traverse_postorder do |l, node|
      level << l
      order << node.segment
      data << node.data
    end
    assert_equal("456231", order)
    assert_equal([2, 2, 2, 1, 1, 0], level)
    assert_equal([124, 125, 126, nil, 13, nil], data)
  end

  def test_levelorder_ok
    root = PathTree.new("1")
    {"1/2/4" => 124,
     "1/2/5" => 125,
     "1/2/6" => 126,
     "1/3" => 13}.each { |p, d|
      root.add_path(p, d)
    }

    order = ""
    data = []
    level = []
    root.traverse_levelorder do |l, node|
      level << l
      order << node.segment
      data << node.data
    end
    assert_equal("123456", order)
    assert_equal([0, 1, 1, 2, 2, 2], level)
    assert_equal([nil, nil, 13, 124, 125, 126], data)
  end

  def test_node
    root = PathTree.new("1")
    {"1/2/4" => 124,
     "1/2/5" => 125,
     "1/2/6" => 126,
     "1/3" => 13}.each { |p, d|
      root.add_path(p, d)
    }

    order = ""
    data = []
    level = []
    node = root.node("1/2")
    node.traverse_preorder do |l, node|
      level << l
      order << node.segment
      data << node.data
    end
    assert_equal("2456", order)
    assert_equal([0, 1, 1, 1], level)
    assert_equal([nil, 124, 125, 126], data)

    node = root.node("1/4")
    assert_nil(node)
  end

  def test_append_tree
    root = PathTree.new("1")
    {"1/2/4" => 124,
     "1/2/5" => 125,
     "1/2/6" => 126,
     "1/3" => 13}.each { |p, d|
      root.add_path(p, d)
    }

    newtree = PathTree.new("3")
    {"3/4" => 34,
     "3/5" => 35,
     "3/6" => 36,
     "3/7/8" => 378}.each { |p, d|
      newtree.add_path(p, d)
    }

    # append newtree to a leaf of root
    n = root.node("1/2/6")
    n.append_tree(newtree)

    order = ""
    data = []
    level = []
    root.traverse_preorder do |l, node|
      level << l
      order << node.segment
      data << node.data
    end
    assert_equal("124563456783", order)
    assert_equal([0, 1, 2, 2, 2, 3, 4, 4, 4, 4, 5, 1], level)
    assert_equal([nil, nil, 124, 125, 126, nil, 34, 35, 36, nil, 378, 13], data)
  end

  def test_append_tree_2
    t = PathTree.new("/1/2")
    t.node("/1/2").append_tree(PathTree.new("my/new/tree"))
    assert_equal(6, t.count)
    assert(!t.node("/1/2/my/new/tree").nil?)

    t.node("/1/").append_tree(PathTree.new("my/new/tree"))
    assert_equal(9, t.count)
    assert(!t.node("/1/my/new/tree").nil?)
  end
  def test_trying_append_existing_path
    root = PathTree.new("1")
    {"1/2/4" => 124,
     "1/2/5" => 125,
     "1/2/6" => 126,
     "1/3" => 13}.each { |p, d|
      root.add_path(p, d)
    }

    newtree = PathTree.new("2")
    {"2/4" => 34,
     "2/5" => 35,
     "2/6" => 36}.each { |p, d|
      newtree.add_path(p, d)
    }

    # try to append newtree to a leaf of root (should fail)
    n = root.node("1")
    assert_raises(ArgumentError) {
      n.append_tree(newtree)
    }

    # successfully append newtree to a leaf of root
    n = root.node("1/2")
    n.append_tree(newtree)
  end

  def test_build_from_fs
    p = PathTree.build_from_fs("#{__dir__}/../.git", prune: true) do |pt|
      pt.extname == ".sample"
    end
    expected_dirs = %w[hooks]
    found_dirs = []
    p.traverse_levelorder do |l, node|
      next unless l == 1 && !node.leaf?

      found_dirs << node.segment
    end
    assert_equal(expected_dirs, found_dirs)
  end
end
