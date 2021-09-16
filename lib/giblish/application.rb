require_relative "cmdline"
require_relative "config_utils"
require_relative "resourcepaths"
require_relative "converters"
require_relative "treeconverter"
require_relative "docid/docid"
require_relative "indexbuilders/depgraphviz"

module Giblish
  # configure all parts needed to execute the options specified by
  # the user
  class Configurator
    attr_reader :tree_converter

    # 1. Source text -> adoc_source
    # 2. API options -> eg backend
    # 3. Doc attribs -> style info, xref style, variables, ...
    #
    # cmd_opts:: a Cmdline::Option instance with user options
    # src_tree:: a Pathtree with the adoc files to convert as leaf nodes
    def initialize(cmd_opts, src_tree)
      build_options = {
        pre_builders: [],
        post_builders: [],
        adoc_api_opts: {},
        # add a hash where all values are initiated as empty arrays
        adoc_extensions: Hash.new { |h, k| h[k] = [] }
      }

      # Initiate the doc attribute repo used during 'run-time'
      doc_attr = DocAttrBuilder.new(
        GiblishDefaultDocAttribs.new
      )

      setup_docid(cmd_opts, build_options, doc_attr)
      setup_index_generation(cmd_opts, build_options, doc_attr)

      # generic format (html/pdf/...) options
      case cmd_opts
        in format: "html", resource_dir:
          # copy local resources to dst and link the generated html with
          # the given css
          build_options[:adoc_api_opts][:backend] = "html"
          build_options[:pre_builders] << CopyResourcesPreBuild.new(cmd_opts)

          # make sure generated html has relative link to the copied css
          doc_attr.add_doc_attr_providers(
            RelativeCssDocAttr.new(
              ResourcePaths.new(cmd_opts).dst_style_path_rel
            )
          )
        in format: "html", web_path:
          # do not copy any local resources, use the given web path to link to css
          build_options[:adoc_api_opts][:backend] = "html"
          doc_attr.add_doc_attr_providers(
            AbsoluteLinkedCss.new(cmd_opts.web_path)
          )

        in format: "html"
          # embed the default asciidoc stylesheet - do nothing
          build_options[:adoc_api_opts][:backend] = "html"

        in format: "pdf", resource_dir:
          # generate pdf using asciidoctor-pdf with custom styling
          build_options[:adoc_api_opts][:backend] = "pdf"

          # enable custom pdf styling
          rp = ResourcePaths.new(cmd_opts)
          doc_attr.add_doc_attr_providers(
            PdfCustomStyle.new(rp.src_style_path_abs, *rp.font_dirs_abs.to_a)
          )
        in format: "pdf"
          # generate pdf using asciidoctor-pdf with default styling
          build_options[:adoc_api_opts][:backend] = "pdf"
        else
          raise OptionParser::InvalidArgument, "The given cmd line flags are not supported: #{cmd_opts.inspect}"
      end

      # handle search data options
      case cmd_opts
        in format: "html", make_searchable: true
          # enabling text search
          search_provider = HeadingIndexer.new(src_tree)
          build_options[:adoc_extensions][:tree_processor] << search_provider
          build_options[:post_builders] << search_provider
        else
          4 == 5 # a dummy statement to prevent a crash of 'standardrb'
      end

      # compose the attribute provider and associate it with all source
      # nodes
      provider = DataDelegator.new(SrcFromFile.new, doc_attr)
      src_tree.traverse_preorder do |level, node|
        next unless node.leaf?

        node.data = provider
      end

      # override doc attributes with ones from cmdline to
      # ensure they have highest pref
      doc_attr.add_doc_attr_providers(CmdLineDocAttribs.new(cmd_opts))

      @tree_converter = TreeConverter.new(
        src_tree,
        cmd_opts.dstdir,
        build_options
      )
    end

    def setup_index_generation(cmd_opts, build_options, doc_attr)
      return if cmd_opts.no_index

      # setup index generation
      idx = IndexTreeBuilder.new(doc_attr, nil, cmd_opts.index_basename)
      build_options[:post_builders] << idx
    end

    def setup_docid(cmd_opts, build_options, doc_attr)
      return unless cmd_opts.resolve_docid

      # setup docid resolution
      d = DocIdExtension::DocidPreBuilder.new
      build_options[:pre_builders] << d
      docid_pp = DocIdExtension::DocidProcessor.new({id_2_node: d.id_2_node})
      build_options[:adoc_extensions][:preprocessor] << docid_pp

      return if cmd_opts.no_index

      # generate dep graph if graphviz is available
      dg = DepGraphDot.new(docid_pp.node_2_ids)
      build_options[:post_builders] << dg
    end
  end

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
          cmdline.include_regex =~ p.to_s
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
    end

    # returns on success, raises otherwise
    def run
      # build a tree of files matching user's regexp selection
      src_tree = PathTree.build_from_fs(@user_opts.srcdir) do |p|
        if @user_opts.exclude_regex&.match(p.to_s)
          false
        else
          @user_opts.include_regex =~ p.to_s
        end
      end
      if src_tree.nil?
        Giblog.logger.warn { "Did not find any files to convert" }
        return
      end

      # setup and execute the conversion
      app = Configurator.new(@user_opts, src_tree)
      app.tree_converter.run
    end
  end

  class GitRepoConvert
    def initialize(user_opts)
      raise ArgumentError, "No selection for git branches or tags were found!" unless user_opts.branch_regex || user_opts.tag_regex

      @repo_root = find_gitrepo_root(user_opts.srcdir)
      raise ArgumentError("The path: #{user_opts.srcdir} is not within a git repo!") if @repo_root.nil?

      # cache the root dir
      @dst_topdir = user_opts.dstdir

      # TODO: parametrize this
      @abort_on_error = true
    end

    def run
      # convert all docs found in the branches/tags that the user asked to parse
      GitCheckoutManager.new(
        git_repo_root: @repo_root,
        local_only: cmdline.local_only,
        branch_regex: cmdline.branch_regex,
        tag_regex: cmdline.tag_regex
      ).each_checkout do |name|
        begin
          Giblog.logger.info { "Working on #{name}" }

          # tweak the destination dir to a subdir per branch/tag
          cmdline.dstdir = @dst_topdir / name.sub("/", "_")

          DirTreeConvert.new(cmdline).run
        rescue => e
          if @abort_on_error
            raise e
          else
            Giblog.logger.error {"Conversion of #{name} failed!"}
            Giblog.logger.error {e.message}
          end
        end
      end
    end

    private

    # Get the log history of the supplied file as an array of
    # hashes, each entry has keys:
    # sha
    # date
    # author
    # email
    # parent
    # message
    def file_log(filename)
      o, e, s = exec_cmd("log", %w[--follow --date=iso --], "'#{filename}'")
      raise "Failed to get git log for #{filename}!!\n#{e}" if s.exitstatus != 0

      process_log_output(o)
    end

    # Process the log output from git
    # (This is copied to 90% from the ruby-git gem)
    def process_log_output(output)
      in_message = false
      hsh_array = []
      hsh = nil

      output.each_line do |line|
        line = line.chomp

        if line[0].nil?
          in_message = !in_message
          next
        end

        if in_message
          hsh["message"] << "#{line[4..]}\n"
          next
        end

        key, *value = line.split
        key = key.sub(":", "").downcase
        value = value.join(" ")

        case key
        when "commit"
          hsh_array << hsh if hsh
          hsh = {"sha" => value, "message" => +"", "parent" => []}
        when "parent"
          hsh["parent"] << value
        when "author"
          tmp = value.split("<")
          hsh["author"] = tmp[0].strip
          hsh["email"] = tmp[1].sub(">", "").strip
        when "date"
          hsh["date"] = DateTime.parse(value)
        else
          hsh[key] = value
        end
      end
      hsh_array << hsh if hsh
      hsh_array
    end

    # Execute engine for git commands,
    # Returns same as capture3 (stdout, stderr, Process.Status)
    def exec_cmd(cmd, flags, args)
      # always add the git dir to the cmd to ensure that git is executed
      # within the expected repo
      gd_flag = "--git-dir=\"#{@git_dir}\""
      wt_flag = "--work-tree=\"#{@repo_root}\""
      flag_str = flags.join(" ")
      git_cmd = "git #{gd_flag} #{wt_flag} #{cmd} #{flag_str} #{args}"
      Giblog.logger.debug { "running: #{git_cmd}" }
      Open3.capture3(git_cmd.to_s)
    end

    # Public: Find the root directory of the git repo in which the
    #         given dirpath resides.
    #
    # dirpath - an absolute path to a directory that resides
    #           within a git repo.
    #
    # Returns: the root direcotry of the git repo or nil if the input path
    #          does not reside within a git repo.
    def find_gitrepo_root(dirpath)
      Pathname.new(dirpath).realpath.ascend do |p|
        git_dir = p.join(".git")
        return p if git_dir.directory?
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

      # Do the conversion
      select_conversion(user_opts).run

      # exit
      Giblog.logger.info { "Giblish is done!" }
    end

    def select_conversion(user_opts)
      case user_opts
        in branch_regex:, tag_regex:
          GitRepoConvert.new(user_opts)
        else
          DirTreeConvert.new(user_opts)
      end
    end
  end
end
