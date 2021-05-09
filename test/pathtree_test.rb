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
end
