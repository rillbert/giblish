require_relative "treeoperators"

require_relative "../test_helper"

module Gran
  class OperatorTest < GranTestBase
    def setup
      @src_top = Pathname.new(__dir__) / ".." / "testdata"
    end

    def test_to_lower
      TmpDocDir.open do |tmp_docs|
        dst_top = Pathname(tmp_docs.dir)
        operator = ToLowerConverter.new(
          src_top: @src_top,
          dst_top: dst_top,
          opts: {extensions: [".bin"]}
        )
        operator.run
        logger.info("\n" + PathTree.build_from_fs(dst_top).to_s)
      end
    end

    def test_first_letter
      TmpDocDir.open(preserve: false) do |tmp_docs|
        dst_top = Pathname(tmp_docs.dir)
        operator = FirstLetterSubtree.new(
          src_top: @src_top,
          dst_top: dst_top
          # opts: {extensions: [".bin"]}
        )
        operator.run
        logger.info("\n" + PathTree.build_from_fs(dst_top).to_s)
      end
    end

    class TestConverter
      def convert(input_stream:, output_stream:)
        output_stream.write(input_stream.read.downcase)
      end
    end

    def test_file_tree
      TmpDocDir.open(preserve: false) do |tmp_docs|
        backing_string = "Hello, World!"
        src_top = Pathname(tmp_docs.dir) / "src"
        src_tree = PathTree.new(src_top)
        src_node = src_tree.find("src")
        ["a.txt", "b.txt", "c.bin", "d.bin"].each do |f|
          src_node[0].add_descendants(f, StringIO.new(backing_string))
        end
        logger.info("\n" + src_tree.to_s)

        dst_top = Pathname(tmp_docs.dir) / "dst"
        dst_tree = PathTree.new(dst_top)

        operator = FileTree.new(
          src_tree: src_tree,
          dst_tree: dst_tree,
          converter: TestConverter.new
        )

        operator.run
        logger.info("\n" + dst_tree.to_s)
      end
    end
  end
end
