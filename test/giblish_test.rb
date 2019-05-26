require "test_helper"

require_relative "../lib/giblish/utils.rb"
require_relative "../lib/giblish/core.rb"

class GiblishAdminTest < Minitest::Test
  def setup
    # setup logging
    Giblog.setup
  end

  def test_that_it_has_a_version_number
    refute_nil ::Giblish::VERSION
  end
end

class PathManagerTest < Minitest::Test
  include Giblish::TestUtils

  def setup
    # setup logging
    Giblog.setup
  end

  def test_src_rel
    TmpDocDir.open do |d|
      root = d.dir

      FileUtils.mkdir_p(Pathname.new(root).join("branch_1/level_1"))
      FileUtils.mkdir_p(Pathname.new(root).join("branch_2/level_1"))

      out = Giblish::PathManager.new("#{root}/branch_2",
                                     "#{root}/branch_1/level_1")

      # test that a fake path raises an exception
      assert_raises Errno::ENOENT do
        out.reldir_from_src_root("/home/kalle/anka.adoc")
      end

      # test that the relative path from src_root to <root> is ".."
      assert_equal Pathname.new(".."), out.reldir_from_src_root(root)
      assert_equal(
          Pathname.new("../branch_1/level_1"),
          out.reldir_from_src_root("#{root}/branch_1/level_1/file.adoc")
      )
      assert_equal(
          Pathname.new("../branch_1/level_1"),
          out.adoc_output_dir("#{root}/branch_2/mytest.adoc")
      )
      assert_equal(
          Pathname.new("../branch_1/level_1"),
          out.adoc_output_dir("#{root}/branch_2")
      )
    end
  end
end
