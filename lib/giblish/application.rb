require_relative "cmdline"
require_relative "pathutils"
require_relative "converters"
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

      # Parse cmd line
      cmdline = CmdLine.new.parse(args)
      Giblog.logger.debug { "cmd line args: #{cmdline.inspect}" }

      execute_conversion(cmdline)
      Giblog.logger.info { "Giblish is done!" }
    end

    # does not return, exits with status code
    def run_from_cmd_line
      begin
        run(ARGV)
        exit_code = 0
      rescue => exc
        Giblog.logger.error { exc.message }
        exit_code = 1
      end
      exit(exit_code)
    end

    private

    def execute_conversion(cmdline)
      # setup conversion options
      conv_options = {
        pre_builders: [],
        post_builders: []
      }

      # enable docid extension if asked for
      resolve_docid(conv_options) if cmdline.resolve_docid

      # convert adoc files on disk
      if cmdline.branch_regex || cmdline.tag_regex
        convert_git_repo(cmdline, conv_options)
      else
        convert_file_tree(cmdline)
      end
    end

    def get_api_opts(cmdline)
      {
        backend: cmdline.format
      }
    end

    def convert_file_tree(cmdline)
      src_tree = tree_from_srcdir(cmdline)
      puts src_tree

      # get an instance of each index_builder the user asked for
      index_builders = create_index_builder(cmdline)

      # setup conversion opts
      conversion_opts = {
        adoc_api_opts: get_api_opts(cmdline),
        adoc_doc_attribs: cmdline.doc_attributes
      }
      conversion_opts[:post_builders] = index_builders unless index_builders.nil?

      # run the conversion of the tree
      tc = TreeConverter.new(src_tree, cmdline.dstdir, conversion_opts)
      tc.run
    end

    def convert_git_repo(cmdline, conv_options)
      # Create a handle to our git interface
      git_itf = Giblish::GitItf.new(repo)

      # convert all docs found in the branches/tags that the user asked to parse
      GitCheckoutManager.new(
        git_repo_root: cmdline.srcdir,
        local_only: cmdline.local_only,
        branch_regex: cmdline.branch_regex,
        tag_regex: cmdline.tag_regex
      ).each_checkout do |name|
        Giblog.logger.info { "Working on #{name}" }

        # sanitize the top-dir name for each branch
        branch_dst = cmdline.dstdir / name.sub("/", "_")

        # get an instance of each index_builder the user asked for
        index_builders = create_index_builder(cmdline)

        # setup conversion opts
        conversion_opts = {}
        conversion_opts[:post_builders] = index_builders unless index_builders.nil?
        conversion_opts[:conversion_cb] = {
          success: ->(src, dst, dst_rel_path, doc, logstr) do
            TreeConverter.on_success(src, dst, dst_rel_path, doc, logstr)

            p = src.pathname.relative_path_from(repo)

            # a bit hackish... These callbacks are also called when converting post-build
            # files. Those files do not reside in the git repo since they're generated and thus we
            # skip those when getting the gitlog
            next if p.to_s.start_with?("..")

            # Get the commit history of the doc
            # (use a homegrown git log to get 'follow' flag)
            git_itf.file_log(p.to_s).each do |i|
              dst.data.history << DocInfo::DocHistory.new(i["date"], i["author"], i["message"])
            end
          end,
          failure: ->(src, dst, dst_rel_path, ex, logstr) { TreeConverter.on_failure(src, dst, dst_rel_path, ex, logstr) }
        }

        # run the conversion of the tree
        tc = TreeConverter.new(st, branch_dst, conversion_opts)
        tc.run
      end
    end

    def convert_files(src, dst, conv_options, converter = nil)
      # setup a PathTree with all complying adoc files
      fs_root = tree_from_src_dir(src)
      st = fs_root.node(repo, from_root: true)

      converter = if converter.nil?
        TreeConverter.new(st, dst, conv_options)
      else
        converter.init_src_dst(st, dst)
      end

      [converter.run, converter]
    end

    def create_index_builder(cmdline)
      return nil if cmdline.no_index

      # TODO: Implement factory depending on cmdline
      IndexTreeBuilder.new(cmdline.dstdir)
    end

    def resolve_docid(conv_options)
      # Create a docid pre-builder/preprocessor and register it with all future TreeConverters
      d_pp = DocIdExtension::DocIdCacheBuilder.new
      TreeConverter.register_adoc_extensions({preprocessor: DocIdExtension::DocidResolver.new({docid_cache: d_pp})})
      conv_options[:pre_builders] << d_pp
    end

    def tree_from_srcdir(cmdline)
      # create the pathtree with the files corresponding to the user filter
      src_tree = PathTree.build_from_fs(cmdline.srcdir, prune: false) do |pt|
        !pt.directory? && cmdline.include_regex =~ pt.to_s
      end

      # add a file reading obj to each file
      src_tree.traverse_preorder do |level, n|
        next unless n.leaf?

        n.data = SrcFromFile.new
      end
      src_tree.node(cmdline.srcdir, from_root: true)
    end
  end
end
