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
    idc = Giblish::DocidCollector.new

    # traverse the src file tree and collect ids from all
    # .adoc or .ADOC files
    Find.find(@paths.src_root_abs) do |path|
      ext = File.extname(path)
      idc.parse_file(path) if !ext.empty? && ext.casecmp(".ADOC").zero?
    end

    puts idc.docid_cache
  end
end
