require_relative "../../lib/gran/loggable"
require_relative "../../lib/gran/pathtree"

module Gran
  #
  # Produce a new tree by converting text files in the source
  # tree to lower case
  #
  class ToLowerConverter
    include Loggable
    #
    # Create a new ToLowerConverter
    #
    # @param [Pathname] src_top  the top directory of the source tree
    # @param [Pathname] dst_top  the top directory of the destination tree
    # @param [Hash{Symbol => Array<String>}] opts         additional options
    # @option opts [Array<String>}] :extensions   List of file extensions to convert,
    # default is [".txt"]
    #
    def initialize(src_top:, dst_top:, opts: {})
      # make sure both src_top and dst_top are Pathnames that points to a directory
      [src_top, dst_top].each do |p|
        raise ArgumentError, "#{p} is not a Pathname" unless p.is_a?(Pathname)
        raise ArgumentError, "#{p} must point to a directory" unless p.directory?
      end

      @src_tree = PathTree.build_from_fs(src_top, prune: false)
      @dst_top = dst_top

      # if the extensions option is not provided, default to .txt
      @opts = opts.merge(extensions: opts.fetch(:extensions, [".txt"]))
      logger.debug { "ToLowerConverter initialized with: #{@opts}" }
    end

    def run(abort_on_exc: true)
      @src_tree.traverse_preorder do |level, n|
        # skip non-leaf nodes
        next unless n.leaf?

        # skip non-text files
        next unless @opts[:extensions].include?(
          n.pathname.extname.downcase
        )

        # create the destination node, using the correct suffix depending on conversion backend
        rel_path = n.relative_path_from(@src_tree)
        dst_path = @dst_top / rel_path
        logger.debug { "Creating file at: #{dst_path}" }

        # create the parent directories if they do not exist
        FileUtils.mkdir_p(dst_path.dirname)

        # read the text file and convert it
        File.open(n.pathname, "r") do |f|
          content = f.read
          File.write(dst_path, content.downcase)
        end
      rescue => exc
        logger.error { "#{n.pathname} - #{exc.message}" }
        raise exc if abort_on_exc
      end
    end
  end

  #
  # Write a new text file that contains the first letter of each
  # file in the source tree that is a text file
  #
  class FirstLetterSubtree
    include Loggable

    def initialize(src_top:, dst_top:, opts: {})
      # make sure both src_top and dst_top are Pathnames that points to a directory
      [src_top, dst_top].each do |p|
        raise ArgumentError, "#{p} is not a Pathname" unless p.is_a?(Pathname)
        raise ArgumentError, "#{p} must point to a directory" unless p.directory?
      end

      @src_tree = PathTree.build_from_fs(src_top, prune: false)
      @dst_top = dst_top

      # if the extensions option is not provided, default to .txt
      @opts = opts.merge(extensions: opts.fetch(:extensions, [".txt"]))
      logger.debug { "ToLowerConverter initialized with: #{@opts}" }
    end

    def run(abort_on_exc: true)
      first_letter_cache = ""
      @src_tree.traverse_postorder do |level, n|
        logger.debug { "Processing: #{n.pathname}" }
        # for leaf nodes, cache the first letter in the file
        if n.leaf? &&
            @opts[:extensions].include?(n.pathname.extname.downcase)
          # read the first letter of the file
          File.open(n.pathname, "r") do |f|
            content = f.read
            first_letter_cache << content[0] if content.length > 0
          end
          next
        end

        unless first_letter_cache.empty?
          # for non-leaf nodes, write the cache to a file
          dst_path = @dst_top / n.relative_path_from(@src_tree)

          # create the parent directories if they do not exist
          FileUtils.mkdir_p(dst_path)

          # write the first letter to a file
          logger.debug { "Writing #{first_letter_cache} to: #{dst_path}" }
          File.write(dst_path / "first_letter.txt", first_letter_cache)
        end
        # reset the cache
        first_letter_cache = ""
      end
    end
  end

  #
  # Each node supports the IO operations that are needed to
  #
  #
  class FileTree
    include Loggable

    def initialize(src_tree:, dst_tree:, converter:)
      # make sure both src_top and dst_top are Pathnames that points to a directory
      # [dst_top].each do |p|
      #   raise ArgumentError, "#{p} is not a Pathname" unless p.is_a?(Pathname)
      #   raise ArgumentError, "#{p} must point to a directory" unless p.directory?
      # end

      @src_tree = src_tree
      @dst_tree = dst_tree
      @converter = converter

      # if the extensions option is not provided, default to .txt
      # @opts = opts.merge(extensions: opts.fetch(:extensions, [".txt"]))
    end

    def run(abort_on_exc: true)
      @src_tree.traverse_postorder do |level, n|
        if n.leaf?
          logger.debug { "Get input stream from #{n.pathname}" }
          output_stream = StringIO.new
          @converter.convert(
            input_stream: n.data,
            output_stream: output_stream
          )

          # add the converted content to the destination tree
          # the output file path is the same as the input file path
          # but relative to the destination top directory
          @dst_tree.add_descendants(
            n.relative_path_from(@src_tree),
            output_stream.string
          )
        end
      end
    end
  end
end
