require "test_helper"
require "fileutils"
require_relative "../lib/giblish/utils.rb"

class PathManagerTest < Minitest::Test

  def setup
    # get abs path to the dir where this file resides
    this_dir = Pathname.new(__FILE__ ).parent.realpath

    # create a file area to hold src and dst trees
    @topdir = this_dir.join("_pathtesttopdir")
    FileUtils.mkdir_p(@topdir)
    @src_root = @topdir.join("src_topdir")
    FileUtils.mkdir_p(@src_root)
    @dst_root= @topdir.join("dst_topdir")
    FileUtils.mkdir_p(@dst_root)

    @resource_rel = Pathname.new("resources")
    @resource_dir = @src_root.join(@resource_rel)
    FileUtils.mkdir_p(@resource_dir)

    # create some subdirs in src
    @src_subdir1 = Pathname.new("subdir1")
    @src_subsub1 = Pathname.new("subdir1/subsub")
    FileUtils.mkdir_p(@src_root.join(@src_subsub1))
    @src_subdir1_abs = @src_root.join(@src_subdir1).realpath
    @src_subsub1_abs = @src_root.join(@src_subsub1).realpath

  end

  def teardown
    FileUtils.rm_rf(@topdir)
  end

  def test_dst_root_abs
    p = Giblish::PathManager.new(@src_root, @dst_root)
    assert_equal Pathname.new(@dst_root), p.dst_root_abs
  end

  def test_src_root_abs
    p = Giblish::PathManager.new(@src_root, @dst_root)
    assert_equal Pathname.new(@src_root), p.src_root_abs
  end

  def test_resource_abs
    p = Giblish::PathManager.new(@src_root, @dst_root)
    assert_nil p.resource_dir_abs

    p = Giblish::PathManager.new(@src_root, @dst_root,@resource_dir)
    assert_equal Pathname.new(@resource_dir), p.resource_dir_abs
  end

  def test_reldir_from_src_root
    p = Giblish::PathManager.new(@src_root, @dst_root)
    assert_equal @src_subsub1, p.reldir_from_src_root(@src_subsub1_abs)

  end
end
