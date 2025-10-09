require "pathname"
require "fileutils"
require_relative "loggable"
require_relative "pathtree"

module Gran
  #
  # A framework for transforming source file trees into destination trees
  # through three distinct phases:
  #
  # 1. SCAN - Examine source tree, collect metadata (read-only)
  # 2. TRANSFORM - Convert source nodes to destination nodes (core work)
  # 3. FINALIZE - Generate derived outputs, aggregations (post-processing)
  #
  # == Usage
  #
  #   transformer = Gran::TreeTransformer.new(
  #     src: "/path/to/source",
  #     dst: "/path/to/destination",
  #     transformer: MyTransformer.new,
  #     traversal: :preorder  # optional, default :preorder
  #   )
  #
  #   # Register scanners and finalizers
  #   transformer.add_scanner(MyScanner.new)
  #   transformer.add_finalizer(MyFinalizer.new)
  #
  #   # Run all phases
  #   transformer.run(abort_on_exc: true)
  #
  # == Transformer Interface
  #
  # Transformers must implement:
  #
  #   def transform(src_node, dst_tree, context)
  #     # Required: perform transformation, mutate dst_tree
  #   end
  #
  #   def should_transform?(src_node, context)
  #     # Optional: return true/false to filter nodes
  #     # Default: true (process all nodes)
  #   end
  #
  # == Scanner Interface
  #
  # Scanners must implement:
  #
  #   def scan(src_tree, context)
  #     # Examine source tree, collect metadata
  #     # Mutate context to share data with transform/finalize phases
  #   end
  #
  # == Finalizer Interface
  #
  # Finalizers must implement:
  #
  #   def finalize(src_tree, dst_tree, transformer, context)
  #     # Generate derived outputs, copy assets, etc.
  #   end
  #
  class TreeTransformer
    include Loggable

    attr_reader :src_tree, :dst_tree, :context, :transformer

    # Create a new TreeTransformer
    #
    # @param [Pathname, String, PathTree] src
    #   Source tree - can be a filesystem path or an existing PathTree
    # @param [Pathname, String] dst
    #   Destination path where transformed output will be created
    # @param [Object] transformer
    #   Object implementing the transformer interface
    # @param [Symbol] traversal
    #   Tree traversal order: :preorder (default), :postorder, or :levelorder
    # @param [Hash] context
    #   Initial context hash for sharing data between phases
    #
    def initialize(src:, dst:, transformer:, traversal: :preorder, context: {})
      @transformer = transformer
      @traversal = traversal
      @context = context

      # Build or accept source tree
      @src_tree = if src.is_a?(PathTree)
        src
      else
        src_path = Pathname.new(src).cleanpath
        raise ArgumentError, "Source path does not exist: #{src_path}" unless src_path.exist?

        PathTree.build_from_fs(src_path, prune: false)
      end

      # Create destination tree
      dst_path = Pathname.new(dst).cleanpath
      @dst_tree = PathTree.new(dst_path)

      # Store root references in context for convenience
      @context[:src_root] = @src_tree
      @context[:dst_root] = @dst_tree

      # Phase handlers
      @scanners = []
      @finalizers = []

      # Validate traversal method
      unless @src_tree.respond_to?("traverse_#{@traversal}")
        raise ArgumentError, "Invalid traversal order: #{@traversal}"
      end
    end

    # Add a scanner to be run during the scan phase
    #
    # @param [Object] scanner
    #   Object implementing the scanner interface (must respond to #scan)
    #
    def add_scanner(scanner)
      raise ArgumentError, "Scanner must respond to #scan" unless scanner.respond_to?(:scan)

      @scanners << scanner
    end

    # Add a finalizer to be run during the finalize phase
    #
    # @param [Object] finalizer
    #   Object implementing the finalizer interface (must respond to #finalize)
    #
    def add_finalizer(finalizer)
      raise ArgumentError, "Finalizer must respond to #finalize" unless finalizer.respond_to?(:finalize)

      @finalizers << finalizer
    end

    # Run all three transformation phases
    #
    # @param [Boolean] abort_on_exc
    #   If true, abort on first exception. If false, log errors and continue.
    #
    def run(abort_on_exc: true)
      logger.info { "Starting tree transformation: #{@src_tree.pathname} -> #{@dst_tree.pathname}" }

      run_scan_phase
      run_transform_phase(abort_on_exc: abort_on_exc)
      run_finalize_phase(abort_on_exc: abort_on_exc)

      logger.info { "Tree transformation complete" }
    end

    private

    # Phase 1: Scan
    # Examine source tree and collect metadata (read-only)
    def run_scan_phase
      return if @scanners.empty?

      logger.debug { "Running scan phase with #{@scanners.length} scanner(s)" }

      @scanners.each do |scanner|
        logger.debug { "Running scanner: #{scanner.class.name}" }
        scanner.scan(@src_tree, @context)
      end
    end

    # Phase 2: Transform
    # Convert source nodes to destination nodes
    def run_transform_phase(abort_on_exc:)
      logger.debug { "Running transform phase (#{@traversal} traversal)" }

      processed = 0
      errors = 0

      @src_tree.send("traverse_#{@traversal}") do |level, src_node|
        # Check if this node should be transformed
        should_process = if @transformer.respond_to?(:should_transform?)
          @transformer.should_transform?(src_node, @context)
        else
          true
        end

        next unless should_process

        # Perform transformation
        @transformer.transform(src_node, @dst_tree, @context)
        processed += 1
      rescue => exc
        errors += 1
        logger.error { "Transform failed for #{src_node.pathname}: #{exc.message}" }
        logger.debug { exc.backtrace.join("\n") }

        raise exc if abort_on_exc
      end

      logger.info { "Transformed #{processed} node(s)" }
      logger.warn { "Encountered #{errors} error(s)" } if errors > 0
    end

    # Phase 3: Finalize
    # Generate derived outputs and finalize the destination tree
    def run_finalize_phase(abort_on_exc:)
      return if @finalizers.empty?

      logger.debug { "Running finalize phase with #{@finalizers.length} finalizer(s)" }

      @finalizers.each do |finalizer|
        logger.debug { "Running finalizer: #{finalizer.class.name}" }
        finalizer.finalize(@src_tree, @dst_tree, @transformer, @context)
      rescue => exc
        logger.error { "Finalizer failed: #{exc.message}" }
        logger.debug { exc.backtrace.join("\n") }

        raise exc if abort_on_exc
      end
    end
  end
end
