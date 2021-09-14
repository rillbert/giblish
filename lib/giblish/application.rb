require_relative "cmdline"
require_relative "config_utils"
require_relative "resourcepaths"
require_relative "converters"
require_relative "treeconverter"
require_relative "docid/docid"

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

      # build a tree of included files
      src_tree = PathTree.build_from_fs(cmdline.srcdir) do |p|
        cmdline.exclude_regex.nil? ? false : cmdline.include_regex =~ p.to_s
      end

      app = Configurator.new(cmdline, src_tree)
      app.tree_converter.run

      # execute_conversion(cmdline)
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
  end
end
