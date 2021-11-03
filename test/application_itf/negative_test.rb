require_relative "../test_helper"
require_relative "../../lib/giblish/resourcepaths"

module Giblish
  class UseCaseTests < GiblishTestBase
    include Giblish::TestUtils

    def test_giberish_file
      TmpDocDir.open(preserve: false) do |tmp_docs|
        topdir = Pathname.new(tmp_docs.dir)
        src_top = topdir / "src"
        src_top.mkpath
        dst_top = topdir / "dst"
        File.open("#{src_top}/test.bin", mode = "wb") { [1, 2, 3].pack("LLL") }

        opts = CmdLine.new.parse(%W[-f html -i "*.bin" #{src_top} #{dst_top}])

        src_tree = PathTree.build_from_fs(Pathname.new(src_top))
        app = Configurator.new(opts)
        convert(src_tree, app)
      end
    end
  end
end
