require_relative "cmdline"
require_relative "configurator"
require_relative "treeconverter"

module Giblish
  # The app class for the giblish application
  class Application
    # returns on success, raises otherwise
    def run(args)
      # force immediate output
      $stdout.sync = true

      # setup logging
      Giblog.setup
      Giblog.logger.level = Logger::INFO

      # Parse cmd line
      cmdline = CmdLine.new.parse(args)
      Giblog.logger.level = cmdline.log_level

      Giblog.logger.debug { "cmd line args: #{cmdline.inspect}" }

      # build a tree of files matching user's regexp selection
      src_tree = PathTree.build_from_fs(cmdline.srcdir) do |p|
        if cmdline.exclude_regex&.match(p.to_s)
          false
        else
          (cmdline.include_regex =~ p.to_s)
        end
      end
      if src_tree.nil?
        Giblog.logger.warn { "Did not find any files to convert" }
        return
      end

      app = Configurator.new(cmdline, src_tree)
      app.tree_converter.run

      Giblog.logger.info { "Giblish is done!" }
    end

    # does not return, exits with status code
    def run_from_cmd_line
      begin
        run(ARGV)
        exit_code = 0
      rescue => exc
        Giblog.logger.error { exc.message }
        Giblog.logger.error { exc.backtrace }
        exit_code = 1
      end
      exit(exit_code)
    end
  end

  class DirTreeConvert
    def initialize(user_opts)
      @user_opts = user_opts
    end

    # returns on success, raises otherwise
    def run(configurator = nil)
      # find our source files
      src_tree = build_src_tree
      return if src_tree.nil?

      # assign/setup a configurator containing all api options and doc attributes
      build_config = configurator || Configurator.new(@user_opts)

      converter = build_config.setup_converter(src_tree)
      converter.run
    end

    private

    # build a tree of files matching user's regexp selection
    def build_src_tree
      o = @user_opts
      pt = PathTree.build_from_fs(o.srcdir) do |p|
        if o.exclude_regex&.match(p.to_s)
          false
        else
          o.include_regex =~ p.to_s
        end
      end
      if pt.nil?
        Giblog.logger.warn { "Did not find any files to convert!" }
        Giblog.logger.warn { "Built srctree using:\n" + %i[@srcdir @include_regex @exclude_regex].collect { |v| "#{v}: #{o.instance_variable_get(v)}" }.join("\n") }
      end
      pt
    end
  end

  class GitRepoConvert
    def initialize(user_opts)
      raise ArgumentError, "No selection for git branches or tags were found!" unless user_opts.branch_regex || user_opts.tag_regex

      @user_opts = user_opts

      @gm = GitCheckoutManager.new(
        srcdir: user_opts.srcdir,
        local_only: user_opts.local_only,
        branch_regex: user_opts.branch_regex,
        tag_regex: user_opts.tag_regex
      )

      # cache the root dir
      @dst_topdir = user_opts.dstdir

      # TODO: parametrize this
      @abort_on_error = true
    end

    def run
      # convert all docs found in the branches/tags that the user asked to parse
      @gm.each_checkout do |name|
        # tweak the destination dir to a subdir per branch/tag
        @user_opts.dstdir = @dst_topdir / name.sub("/", "_")

        Giblog.logger.debug { "cmdline: #{@user_opts.inspect}" }
        DirTreeConvert.new(@user_opts).run
      rescue => e
        if @abort_on_error
          raise e
        else
          Giblog.logger.error { "Conversion of #{name} failed!" }
          Giblog.logger.error { e.message }
        end
      end
    end
  end

  class EntryPoint
    def initialize(args)
      # force immediate output
      $stdout.sync = true

      # setup logging
      Giblog.setup
      Giblog.logger.level = Logger::INFO

      # Parse cmd line
      user_opts = CmdLine.new.parse(args)
      Giblog.logger.level = user_opts.log_level
      Giblog.logger.debug { "cmd line args: #{user_opts.inspect}" }

      # Select the coversion instance to use
      @converter = select_conversion(user_opts)
    end

    def run
      # do the conversion
      @converter.run
    end

    def self.run(args)
      EntryPoint.new(args).run
    end

    # does not return, exits with status code
    def self.run_from_cmd_line
      begin
        EntryPoint.run(ARGV)
        Giblog.logger.info { "Giblish is done!" }
        exit_code = 0
      rescue => exc
        Giblog.logger.error { exc.message }
        Giblog.logger.error { exc.backtrace }
        exit_code = 1
      end
      exit(exit_code)
    end

    private

    def select_conversion(user_opts)
      case user_opts
        in {branch_regex: _} | {tag_regex: _}
          GitRepoConvert.new(user_opts)
        else
          DirTreeConvert.new(user_opts)
      end
    end
  end
end
