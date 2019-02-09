require "test_helper"
require_relative "../lib/giblish/utils.rb"
require_relative "../lib/giblish/docid.rb"

class DocidCollectorTest < Minitest::Test

  def setup
    # setup logging
    Giblog.setup

    # find test directory path
    @testdir_path = File.expand_path(File.dirname(__FILE__))

    @src_root = "#{@testdir_path}/../data/testdocs"
    @dst_root = "#{@testdir_path}/../testoutput"
    FileUtils.mkdir_p @dst_root

    # Instanciate a path manager with
    # source root ==  .../giblish/data/testdocs and
    # destination root == .../giblish/test/testoutput
    @paths = Giblish::PathManager.new(@src_root,
                                      @dst_root)
  end

  def teardown
    # FileUtils.rm_r @dst_root
  end

  def test_collect_docids
    args = ["--log-level",
            "debug",
            "-d",
            @src_root,
            @dst_root]
    Giblish.application.run_with_args args

#    src_root_path = @paths.src_root_abs + "wellformed/docidtest"
    # src_root_path = @paths.src_root_abs

  end
end
