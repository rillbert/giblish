require "test_helper"

require_relative "../lib/giblish/utils.rb"
require_relative "../lib/giblish/core.rb"

class GiblishAdminTest < Minitest::Test
  def setup
    # setup logging
    Giblog.setup

    # find test directory path
    @testdir_path = File.expand_path(File.dirname(__FILE__))
  end

  def test_that_it_has_a_version_number
    refute_nil ::Giblish::VERSION
  end
end

class PathManagerTest < Minitest::Test
  def setup
    # setup logging
    Giblog.setup

    # find test directory path
    @testdir_path = Pathname.new(__dir__).realpath
  end

  def test_src_rel
    # Instanciate a path manager with well source root == .../giblish and
    # destination root == .../giblish/test/testoutput
    out = Giblish::PathManager.new("#{@testdir_path}/..",
                                   "#{@testdir_path}/testoutput")

    # test that a fake path raises an exception
    assert_raises Errno::ENOENT do
      out.reldir_from_src_root("/home/kalle/anka.adoc")
    end

    # test that the relative path from src_dir to @testdir_path is ".."
    assert_equal Pathname.new("test"), out.reldir_from_src_root(@testdir_path)
    assert_equal(
      Pathname.new("lib/giblish"),
      out.reldir_from_src_root("#{@testdir_path}/../lib/giblish/file.adoc")
    )
    assert_equal(
      Pathname.new("test"),
      out.adoc_output_dir("#{@testdir_path}/mytest.adoc")
    )
    assert_equal(
      Pathname.new("test"),
      out.adoc_output_dir(@testdir_path)
    )
  end
end
