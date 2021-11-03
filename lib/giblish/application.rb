require_relative "cmdline"
require_relative "configurator"
require_relative "treeconverter"
require_relative "gitrepos/checkoutmanager"

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
    # This class provides a file as the source for the asciidoc info and
    # sets the document attributes required by Asciidoctor to resolve
    # 'imagesdir' et al.
    class AdocFileProvider
      def adoc_source(src_node, dst_node, dst_top)
        File.read(src_node.pathname)
      end

      def document_attributes(src_node, dst_node, dst_top)
        p = src_node.pathname
        {
          "docfile" => p.to_s,
          "docdir" => p.dirname.to_s,
          "docname" => p.basename.to_s
        }
      end
    end

    def initialize(user_opts)
      @user_opts = user_opts.dup

      # get all adoc source files from disk
      o = @user_opts
      @src_tree = build_src_tree(o.srcdir, o.include_regex, o.exclude_regex)
    end

    # returns on success, raises otherwise
    def run(configurator = nil)
      return if @src_tree.nil?

      # assign/setup a configurator containing all api options and doc attributes
      build_config = configurator || Configurator.new(@user_opts)

      tc = setup_converter(@src_tree, AdocFileProvider.new, build_config)
      tc.run
    end

    private

    # build a tree of files matching user's regexp selection
    def build_src_tree(srcdir, include_regex, exclude_regex)
      pt = PathTree.build_from_fs(srcdir) do |p|
        if exclude_regex&.match(p.to_s)
          false
        else
          include_regex =~ p.to_s
        end
      end
      if pt.nil?
        Giblog.logger.warn { "Did not find any files to convert!" }
        Giblog.logger.warn { "Built srctree using srcdir: #{srcdir} include_regex: #{include_regex} exclude_regex: #{exclude_regex}" }
      end
      pt
    end

    def setup_converter(src_tree, adoc_src_provider, configurator)
      # compose the doc attribute provider.
      configurator.doc_attr.add_doc_attr_providers(adoc_src_provider)
      # NOTE: The order in the line below is important!
      data_provider = DataDelegator.new(configurator.doc_attr, adoc_src_provider)

      # associate the data providers with each source node in the tree
      src_tree.traverse_preorder do |level, node|
        next unless node.leaf?

        node.data = data_provider
      end

      TreeConverter.new(src_tree, @user_opts.dstdir, configurator.build_options)
    end
  end

  # Converts a number of branches/tags in a gitrepo according to the given
  # options.
  # 
  # Each branch/tag is converted into a subdir of the given root dir and a 
  # summary page with links to the converted docs for each branch/tag is
  # generated within the root dir.
  class GitRepoConvert
    def initialize(user_opts)
      raise ArgumentError, "No selection for git branches or tags were found!" unless user_opts.branch_regex || user_opts.tag_regex

      @user_opts = user_opts.dup

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
        @user_opts.dstdir = @dst_topdir / Giblish.to_fs_str(name)

        Giblog.logger.debug { "cmdline: #{@user_opts.inspect}" }
        configurator = GitRepoConfigurator.new(@user_opts, @gm.repo_root)
        DirTreeConvert.new(@user_opts).run(configurator)
      rescue => e
        Giblog.logger.error { "Conversion of #{name} failed!" }
        Giblog.logger.error { e.message }
        raise e if @abort_on_error
      end
      make_summary
    end

    def make_summary
      # reset the dst dir to the user-given-top
      @user_opts.dstdir = @dst_topdir

      # Make sure the summary page is just 'bare-bone'
      @user_opts.make_searchable = nil
      @user_opts.copy_asset_folders = nil
      @user_opts.no_index = true
      @user_opts.resolve_docid = false
      @user_opts.doc_attributes["table-caption"] = nil

      # assign/setup the doc_attr and layout using the same user options as
      # for the adoc source files on each checkout
      conf = Configurator.new(@user_opts)
      s = @gm.summary_provider
      s.index_basename = conf.config_opts.index_basename
      data_provider = DataDelegator.new(
        SrcFromString.new(s.source),
        conf.doc_attr
      )
      srctree = PathTree.new("/" + conf.config_opts.index_basename + ".adoc", data_provider)
      TreeConverter.new(srctree, @dst_topdir, conf.build_options).run
    end
  end

  class EntryPoint
    def initialize(args)
      # force immediate output
      # $stdout.sync = true

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
