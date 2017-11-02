require "test_helper"
require_relative "../lib/giblish/utils.rb"
require_relative "../lib/giblish/docid.rb"

class DocidCollectorTest < Minitest::Test
  def setup
    # setup logging
    Giblog.setup

    # find test directory path
    @testdir_path = File.expand_path(File.dirname(__FILE__))

    # Instanciate a path manager with
    # source root ==  .../giblish/data/testdocs and
    # destination root == .../giblish/test/testoutput
    @paths = Giblish::PathManager.new("#{@testdir_path}/../data/testdocs",
                                      "#{@testdir_path}/testoutput")
  end

  def test_collect_docids
    args = ["--log-level",
            "debug",
            "#{@testdir_path}/../data/testdocs",
            "#{@testdir_path}/testoutput"]
    Giblish.application.run_with_args args

#    src_root_path = @paths.src_root_abs + "wellformed/docidtest"
    # src_root_path = @paths.src_root_abs

  end
end
