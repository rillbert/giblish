require "test_helper"
require "fileutils"
require_relative "../lib/giblish/pathtree"

class PathTreeTest < Minitest::Test
  include Giblish::TestUtils

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

  def test_empty_tree
    t = PathTree.new
    assert_equal(0, t.children.length)
    assert_nil(t.parent)
    assert_nil(t.name)
    assert_equal(Pathname.new(""), t.pathname)
    c = 0
    t.traverse_preorder { |level, node| c += 1 }
    t.traverse_postorder { |level, node| c += 1 }
    assert_equal(2, c)
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
      order << node.name
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
      order << node.name
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
      order << node.name
      data << node.data
    end
    assert_equal("123456", order)
    assert_equal([0, 1, 1, 2, 2, 2], level)
    assert_equal([nil, nil, 13, 124, 125, 126], data)
  end

  def test_subtree
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
    subtree = root.subtree("1/2")
    subtree.traverse_preorder do |l, node|
      level << l
      order << node.name
      data << node.data
    end
    assert_equal("2456", order)
    assert_equal([0, 1, 1, 1], level)
    assert_equal([nil, 124, 125, 126], data)

    subtree = root.subtree("1/4")
    assert_nil(subtree)
  end

  def test_add_tree
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
    n = root.subtree("1/2/6")
    n.add_tree(newtree)

    order = ""
    data = []
    level = []
    root.traverse_preorder do |l, node|
      level << l
      order << node.name
      data << node.data
    end
    assert_equal("124563456783", order)
    assert_equal([0, 1, 2, 2, 2, 3, 4, 4, 4, 4, 5, 1], level)
    assert_equal([nil, nil, 124, 125, 126, nil, 34, 35, 36, nil, 378, 13], data)
  end
end
