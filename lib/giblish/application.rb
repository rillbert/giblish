# frozen_string_literal: true

require_relative "cmdline"
require_relative "core"
require_relative "pathutils"

module Giblish
  class NewApplication
    def initialize(cmdline)
    end

    # return exit status (0 for success)
    def run(args)
      # force immediate output
      $stdout.sync = true

      # setup logging
      Giblog.setup

      # Parse cmd line
      cmdline = CmdLine.new.parse(args)
      Giblog.logger.debug { "cmd line args: #{cmdline.inspect}" }

      exit_code = execute_conversion(cmdline)
      Giblog.logger.info { "Giblish is done!" } if exit_code.zero?
      exit_code
    end

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
        tc = TreeConverter.new(st, branch_dst,conversion_opts)
        tc.run
      end
    end

    private

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

    def setup_index_options
      # remove all src nodes and reset to a fresh builder
      index_builder = IndexTreeBuilder.new(dst)

      conv_options[:post_builders] << index_builder
      return unless cmdline.branch_regex || cmdline.tag_regex

      # add index options for a git repo
      conv_options.merge!(
        {
          conversion_cb: {
            success: ->(src, dst, dst_rel_path, doc, logstr) do
              # use the original implementation to get basic info
              TreeConverter.on_success(src, dst, dst_rel_path, doc, logstr)

              # Get the commit history of the doc
              # (use a homegrown git log to get 'follow' flag)
              gi = Giblish::GitItf.new(repo)
              p = src.pathname.relative_path_from(repo)
              gi.file_log(p.to_s).each do |i|
                dst.data.history << DocInfo::DocHistory.new(i["date"], i["author"], i["message"])
              end
            end,
            failure: ->(src, dst, dst_rel_path, ex, logstr) { TreeConverter.on_failure(src, dst, dst_rel_path, ex, logstr) }
          }
        }
      )
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

        n.data = AdocSrcFromFile.new(n)
      end
      src_tree
    end
  end

  # The 'main' class of giblish
  class Application
    # does not return, exits with status code
    def run_from_cmd_line
      status = run(ARGV)
      exit(status)
    end

    # return exit status (0 for success)
    def run(args)
      # force immediate output
      $stdout.sync = true

      # setup logging
      Giblog.setup

      # Parse cmd line
      cmdline = CmdLineParser.new args
      Giblog.logger.debug { "cmd line args: #{cmdline.args}" }

      exit_code = execute_conversion(cmdline)
      Giblog.logger.info { "Giblish is done!" } if exit_code.zero?
      exit_code
    end

    private

    # Convert using given args
    # return exit code (0 for success)
    def execute_conversion(cmdline)
      conv_ok = true
      begin
        conv_ok = converter_factory(cmdline).convert
      rescue => e
        log_error e
        conv_ok = false
      end
      conv_ok ? 0 : 1
    end

    # return the converter corresponding to the given cmd line
    # options
    def converter_factory(cmdline)
      if cmdline.args[:gitRepoRoot]
        Giblog.logger.info { "User asked to parse a git repo" }
        GitRepoConverter.new(cmdline.args)
      else
        FileTreeConverter.new(cmdline.args)
      end
    end

    def log_error(exc)
      Giblog.logger.error do
        <<~ERR_MSG
          Error: #{exc.message}
          Backtrace:
          \t#{exc.backtrace.join("\n\t")}

          cmdline.usage
        ERR_MSG
      end
    end
  end
end
