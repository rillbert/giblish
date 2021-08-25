require_relative "cmdline"
require_relative "pathutils"
require_relative "converters"
require_relative "treeconverter"

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
        adoc_extensions: Hash.new {|hash, key| hash.key?(key) ? hash[key] : hash[key] = [] }
      }

      # Initiate the doc attribute repo used during 'run-time'
      doc_attr = DocAttrBuilder.new(
        GiblishDefaultDocAttribs.new
      )

      setup_common_stuff(cmd_opts, build_options, doc_attr)

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
          doc_attr.add_doc_attr_providers(
            PdfCustomStyle.new(
              ResourcePaths.new(cmd_opts).src_style_path_abs, p.font_dirs_abs
            )
          )
        in format: "pdf"
          # generate pdf using asciidoctor-pdf with default styling
          build_options[:adoc_api_opts][:backend] = "pdf"
        else
          raise OptionParser::InvalidArgument, "The given cmd line flags are not supported: #{cmd_opts.inspect}"
      end

      case cmd_opts
        in format: "html", make_searchable:
          # enabling text search
          attr = cmd_opts.doc_attributes
          search_cache = SearchDataCache.new(
            file_tree: src_tree,
            id_prefix: (attr.nil? ? nil : attr.fetch("idprefix", nil)),
            id_separator: (attr.nil? ? nil : attr.fetch("idseparator", nil))
          )
          build_options[:post_builders] << search_cache
          build_options[:adoc_extensions][:tree_processor] << HeadingIndexer.new(search_cache)
          # build_options[:adoc_extensions][:tree_processor] << TestAttribs.new
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

    def setup_common_stuff(cmd_opts, build_options, doc_attr)
      # always resolve docid
      d = DocIdExtension::DocIdCacheBuilder.new
      build_options[:pre_builders] << d
      build_options[:adoc_extensions][:preprocessor] << DocIdExtension::DocidResolver.new({docid_cache: d})

      # always generate index
      idx = IndexTreeBuilder.new(doc_attr)
      build_options[:post_builders] << idx
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

    def get_doc_attribs(cmdline)
      if cmdline.web_path
        style_path = cmdline.web_path

      end

      # return the correct document_attribute provider instance
      # depending on format
      if cmdline.resource_dir && cmdline.style_name
        format_config = {"html" => ["css", ".css"], "pdf" => ["pdftheme", ".yml"]}
        config = format_config[cmdline.format]
        style_path = cmdline.resource_dir / config[0] / Pathname.new(cmdline.style_name).sub_ext(config[1])
        raise ArgumentError, "Could not find requested style info at #{style_path}" unless style_path.exist?

        case cmdline.format
        when "html"
          style_path = (cmdline.dstdir / "web_assets/css" / cmdline.style_name).sub_ext(".css")
          RelativeCssDocAttr.new(style_path)
        when "pdf"
          PdfCustomStyle.new(style_path, cmdline.resource_dir / "fonts")
        when "epub"
          raise NotYetImplemented
        end
      end
    end

    def convert_file_tree(cmdline)
      # create the pathtree with the files corresponding to the user filter
      src_tree = PathTree.build_from_fs(cmdline.srcdir, prune: false) do |pt|
        !pt.directory? && cmdline.include_regex =~ pt.to_s
      end
      src_tree = src_tree.node(cmdline.srcdir, from_root: true)

      # add a data provider to each document node
      data_proxy = DataDelegator.new(
        SrcFromFile.new,
        get_doc_attribs(cmdline)
      )
      src_tree.traverse_preorder do |level, n|
        next unless n.leaf?

        n.data = data_proxy
      end

      Giblog.logger.debug src_tree.to_s

      # get an instance of each index_builder the user asked for
      index_builders = create_index_builder(cmdline)

      # setup conversion opts
      conversion_opts = {
        adoc_api_opts: get_api_opts(cmdline)
        # adoc_doc_attribs: cmdline.doc_attributes
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
    end
  end
end
