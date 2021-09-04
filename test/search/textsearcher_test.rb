require_relative "../test_helper"
require_relative "../../lib/giblish/search/headingindexer"

module Giblish
  class TestTextSearcher < Minitest::Test
    include Giblish::TestUtils

    def setup
      Giblog.setup
    end

    def with_search_testdata
      TmpDocDir.open do |tmpdocdir|
        # srcdir = Pathname.new(tmpdocdir.dir) / "src"
        dstdir = Pathname.new(tmpdocdir.dir) / "dst"
        puts `lib/giblish.rb --log-level info -f html -m data/testdocs/wellformed/search #{dstdir}`
        assert_equal 0, $?.exitstatus

        dst_tree = PathTree.build_from_fs(dstdir, prune: false)
        yield(dst_tree)
      end
    end

    def test_basic_search_info
      with_search_testdata do |dsttree|
        db = dsttree.node("search_assets/heading_db.json")
        data = JSON.parse(File.read(db.pathname.to_s), symbolize_names: true)

        # two files expected
        assert_equal(2, data[:fileinfos].length)
        expected_title_lines = {"file1.adoc" => 1, "subdir/file2.adoc" => 2}
        data[:fileinfos].each do |info|
          assert(["file1.adoc", "subdir/file2.adoc"].include?(info[:filepath]))
          puts info.inspect
          assert_equal(
            expected_title_lines[info[:filepath]], 
            info[:sections][0][:line_no])
        end
      end
    end
  end
end
