require_relative "../lib/gran/tree_transformer"
require "test_helper"
require "stringio"

module Gran
  class TreeTransformerTest < GranTestBase
    def setup
      @src_top = Pathname.new(__dir__) / "testdata"
    end

    # Simple transformer that converts text files to uppercase
    class UppercaseTransformer
      def should_transform?(src_node, context)
        src_node.leaf? && src_node.pathname.extname == ".txt"
      end

      def transform(src_node, dst_tree, context)
        # Mirror the structure
        rel_path = src_node.relative_path_from(context[:src_root])
        dst_node = dst_tree.add_descendants(rel_path)

        # Read and convert
        content = File.read(src_node.pathname)
        dst_node.data = content.upcase

        # Track what we processed
        context[:processed] ||= []
        context[:processed] << src_node.pathname.to_s
      end
    end

    # Scanner that counts files by extension
    class FileCounter
      def scan(src_tree, context)
        context[:file_counts] = Hash.new(0)

        src_tree.traverse_preorder do |level, node|
          next unless node.leaf?

          ext = node.pathname.extname
          context[:file_counts][ext] += 1
        end
      end
    end

    # Finalizer that creates a summary file
    class SummaryFinalizer
      def finalize(src_tree, dst_tree, transformer, context)
        summary_node = dst_tree.add_descendants("summary.txt")
        summary_node.data = "Processed #{context[:processed]&.count || 0} files\n"

        if context[:file_counts]
          summary_node.data += "File counts: #{context[:file_counts].inspect}\n"
        end
      end
    end

    def test_basic_transformation
      TmpDocDir.open(preserve: false) do |tmp_docs|
        dst_top = Pathname(tmp_docs.dir)

        transformer = TreeTransformer.new(
          src: @src_top,
          dst: dst_top,
          transformer: UppercaseTransformer.new
        )

        transformer.run

        # Check that context was populated
        assert transformer.context[:processed].is_a?(Array)
        assert transformer.context[:processed].count > 0
        logger.info { "Processed: #{transformer.context[:processed]}" }

        # Check that dst tree was created
        assert transformer.dst_tree.count > 0
        logger.info("\n" + transformer.dst_tree.to_s)
      end
    end

    def test_with_scanner
      TmpDocDir.open(preserve: false) do |tmp_docs|
        dst_top = Pathname(tmp_docs.dir)

        transformer = TreeTransformer.new(
          src: @src_top,
          dst: dst_top,
          transformer: UppercaseTransformer.new
        )

        transformer.add_scanner(FileCounter.new)
        transformer.run

        # Check that scanner populated context
        assert transformer.context[:file_counts].is_a?(Hash)
        assert transformer.context[:file_counts][".txt"] > 0
        logger.info { "File counts: #{transformer.context[:file_counts]}" }
      end
    end

    def test_with_finalizer
      TmpDocDir.open(preserve: false) do |tmp_docs|
        dst_top = Pathname(tmp_docs.dir)

        transformer = TreeTransformer.new(
          src: @src_top,
          dst: dst_top,
          transformer: UppercaseTransformer.new
        )

        transformer.add_scanner(FileCounter.new)
        transformer.add_finalizer(SummaryFinalizer.new)
        transformer.run

        # Check that finalizer created summary node
        logger.info("\nDestination tree:\n" + transformer.dst_tree.to_s)
        summary = transformer.dst_tree.node(Pathname.new("summary.txt"), from_root: false)
        refute_nil summary
        assert summary.data.include?("Processed")
        assert summary.data.include?("File counts:")
        logger.info { "Summary:\n#{summary.data}" }
      end
    end

    def test_postorder_traversal
      TmpDocDir.open(preserve: false) do |tmp_docs|
        dst_top = Pathname(tmp_docs.dir)

        # Track the order of processing
        order_tracker = Class.new do
          attr_reader :order

          def initialize
            @order = []
          end

          def transform(src_node, dst_tree, context)
            @order << src_node.pathname.basename.to_s
          end
        end.new

        transformer = TreeTransformer.new(
          src: @src_top,
          dst: dst_top,
          transformer: order_tracker,
          traversal: :postorder
        )

        transformer.run

        # In postorder, children come before parents
        # So we should see files before directories
        assert order_tracker.order.count > 0
        logger.info { "Postorder processing: #{order_tracker.order.join(', ')}" }
      end
    end

    def test_error_handling_with_abort
      TmpDocDir.open(preserve: false) do |tmp_docs|
        dst_top = Pathname(tmp_docs.dir)

        failing_transformer = Class.new do
          def transform(src_node, dst_tree, context)
            raise "Intentional failure"
          end
        end.new

        transformer = TreeTransformer.new(
          src: @src_top,
          dst: dst_top,
          transformer: failing_transformer
        )

        # Should raise exception when abort_on_exc is true
        assert_raises(RuntimeError) do
          transformer.run(abort_on_exc: true)
        end
      end
    end

    def test_error_handling_continue
      TmpDocDir.open(preserve: false) do |tmp_docs|
        dst_top = Pathname(tmp_docs.dir)

        failing_transformer = Class.new do
          def initialize
            @call_count = 0
          end

          def transform(src_node, dst_tree, context)
            @call_count += 1
            raise "Intentional failure"
          end

          attr_reader :call_count
        end.new

        transformer = TreeTransformer.new(
          src: @src_top,
          dst: dst_top,
          transformer: failing_transformer
        )

        # Should not raise exception when abort_on_exc is false
        transformer.run(abort_on_exc: false)

        # But should have tried to process nodes
        assert failing_transformer.call_count > 0
        logger.info { "Processed #{failing_transformer.call_count} nodes despite errors" }
      end
    end

    def test_context_passing
      TmpDocDir.open(preserve: false) do |tmp_docs|
        dst_top = Pathname(tmp_docs.dir)

        scanner = Class.new do
          def scan(src_tree, context)
            context[:scanned] = true
            context[:scan_time] = Time.now
          end
        end.new

        transformer_impl = Class.new do
          def transform(src_node, dst_tree, context)
            # Transformer can access scanner data
            raise "Scanner didn't run" unless context[:scanned]
            context[:transformed] = true
          end
        end.new

        finalizer = Class.new do
          def finalize(src_tree, dst_tree, transformer, context)
            # Finalizer can access both scanner and transformer data
            raise "Scanner didn't run" unless context[:scanned]
            raise "Transformer didn't run" unless context[:transformed]
            context[:finalized] = true
          end
        end.new

        transformer = TreeTransformer.new(
          src: @src_top,
          dst: dst_top,
          transformer: transformer_impl
        )

        transformer.add_scanner(scanner)
        transformer.add_finalizer(finalizer)
        transformer.run

        # All phases should have run and shared context
        assert transformer.context[:scanned]
        assert transformer.context[:transformed]
        assert transformer.context[:finalized]
        assert transformer.context[:scan_time].is_a?(Time)
      end
    end
  end
end
