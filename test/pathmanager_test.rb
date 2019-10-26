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
    @src_root_rel = Pathname.new("src_topdir")
    @src_root = @topdir.join(@src_root_rel)
    FileUtils.mkdir_p(@src_root)
    @dst_root_rel = Pathname.new("dst_topdir")
    @dst_root= @topdir.join(@dst_root_rel)
    FileUtils.mkdir_p(@dst_root)

    @src_root_file_path = @src_root.join("file1.adoc")
    f = File.new(@src_root_file_path, "w")
    f.close

    @resource_rel = Pathname.new("resources")
    @resource_dir = @src_root.join(@resource_rel)
    FileUtils.mkdir_p(@resource_dir)

    # create some subdirs in src
    @src_subdir1 = Pathname.new("subdir1")
    @src_subsub1 = Pathname.new("subdir1/subsub")
    FileUtils.mkdir_p(@src_root.join(@src_subsub1))
    @src_subdir1_abs = @src_root.join(@src_subdir1).realpath
    @src_subsub1_abs = @src_root.join(@src_subsub1).realpath

    @src_subsub_file_path = @src_subsub1_abs.join("file2.adoc")
    f = File.new(@src_subsub_file_path, "w")
    f.close
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
    assert_equal Pathname.new("."), p.reldir_from_src_root(@src_root)
    assert_equal Pathname.new(".."), p.reldir_from_src_root(@src_root.join(".."))

    assert_equal @src_subsub1, p.reldir_from_src_root(@src_subsub1_abs.join("fakefile.txt"))
  end

  def test_reldir_to_src_root
    p = Giblish::PathManager.new(@src_root, @dst_root)
    assert_equal Pathname.new("../.."), p.reldir_to_src_root(@src_subsub1_abs)
    assert_equal Pathname.new("."), p.reldir_to_src_root(@src_root)
    assert_equal @src_root.relative_path_from(@topdir), p.reldir_to_src_root(@src_root.join(".."))

    assert_equal Pathname.new("../.."), p.reldir_to_src_root(@src_subsub1_abs.join("fakefile.txt"))
    assert_equal Pathname.new("../.."), p.reldir_to_src_root(@src_subsub1_abs.to_s)
  end

  def test_reldir_from_dst_root
    p = Giblish::PathManager.new(@src_root, @dst_root)
    assert_equal Pathname.new("..").join(@src_root_rel).join(@src_subsub1), p.reldir_from_dst_root(@src_subsub1_abs)
    assert_equal Pathname.new("..").join(@src_root_rel), p.reldir_from_dst_root(@src_root)
    assert_equal Pathname.new(".."), p.reldir_from_dst_root(@src_root.join(".."))

    assert_equal Pathname.new("..").join(@src_root_rel).join(@src_subsub1), p.reldir_from_dst_root(@src_subsub1_abs.join("fakefile.txt"))
  end

  def test_reldir_to_dst_root
    p = Giblish::PathManager.new(@src_root, @dst_root)
    assert_equal Pathname.new("../../..").join(@dst_root_rel), p.reldir_to_dst_root(@src_subsub1_abs)
    assert_equal Pathname.new("..").join(@dst_root_rel), p.reldir_to_dst_root(@src_root)
    assert_equal @dst_root_rel, p.reldir_to_dst_root(@src_root.join(".."))

    assert_equal Pathname.new("../../..").join(@dst_root_rel), p.reldir_to_dst_root(@src_subsub1_abs.join("fakefile.txt"))
  end

  def test_dst_abs_from_src_abs
    p = Giblish::PathManager.new(@src_root, @dst_root)
    assert_equal Pathname.new(@dst_root).join(@src_subsub1), p.dst_abs_from_src_abs(@src_subsub1_abs)
    assert_equal Pathname.new(@dst_root).join(@src_subsub1), p.dst_abs_from_src_abs(@src_subsub_file_path)
  end

  def test_relpath_to_dir_after_generate
    p = Giblish::PathManager.new(@src_root, @dst_root)
    assert_equal Pathname.new("../.."), p.relpath_to_dir_after_generate(@src_subsub_file_path,@dst_root)
    assert_equal Pathname.new("."), p.relpath_to_dir_after_generate(@src_root_file_path,@dst_root)
  end

end
