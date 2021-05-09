# frozen_string_literal: true

require "pathname"

require_relative "docconverter"
require_relative "docinfo"
require_relative "docid"
require_relative "search/headingindexer"
require_relative "indexbuilders/buildindex"
require_relative "buildgraph"

module Giblish
  # Parse a directory tree and convert all asciidoc files matching the
  # supplied critera to the supplied format
  class FileTreeConverter
    attr_reader :converter

    # Required options:
    #  srcDirRoot
    #  dstDirRoot
    #  resourceDir
    def initialize(options)
      @options = options.dup

      # setup relevant paths
      @paths = Giblish::PathManager.new(@options[:srcDirRoot], @options[:dstDirRoot],
        @options[:resourceDir], @options[:makeSearchable])

      # assemble the set of files that we shall process
      @adoc_files = CachedPathSet.new(@paths.src_root_abs, &method(:adocfile?)).paths
      @docinfo_store = DocInfoStore.new(@paths)

      # register add-ons for handling searchability if needed
      manage_searchability(@options) if @options[:makeSearchable]

      @deployment_info = setup_deployment_info

      @converter = converter_factory

      @postprocessors = PostProcessors.new(@docinfo_store, @paths, @converter)
      setup_postprocessors(@options)
    end

    # convert all adoc files
    # return true if all conversions went ok, false if at least one
    # failed
    def convert
      # collect all doc ids and enable replacement of known doc ids with
      # valid references to adoc files
      manage_doc_ids if @options[:resolveDocid]

      # traverse the src file tree and convert all files deemed as
      # adoc files
      conv_ok = convert_all_files

      # deploy data needed for search if used
      @search_data_provider&.deploy_search_assets

      # run all postprocessors
      @postprocessors.run(Giblish::AsciidoctorLogger.new(Logger::Severity::WARN))

      conv_ok
    end

    protected

    def convert_all_files
      conv_ok = true
      @adoc_files.each do |p|
        to_asciidoc(p)
      rescue => e
        str = String.new("Error when converting file "\
                         "#{p}: #{e.message}\nBacktrace:\n")
        e.backtrace.each { |l| str << "   #{l}\n" }
        Giblog.logger.error { str }
        conv_ok = false
      end
      conv_ok
    end

    def build_graph_page
      begin
        adoc_logger = Giblish::AsciidoctorLogger.new Logger::Severity::WARN
        gb = graph_builder_factory
        errors = @converter.convert_str(
          gb.source(make_searchable: @options[:makeSearchable]),
          @paths.dst_root_abs,
          "graph",
          logger: adoc_logger
        )
        gb.cleanup
        !errors
      rescue => e
        Giblog.logger.warn { e.message }
        Giblog.logger.warn { "The dependency graph will not be generated !!" }
      end
      false
    end

    def graph_builder_factory
      Giblish::GraphBuilderGraphviz.new @docinfo_store.doc_infos, @paths, @deployment_info,
        @converter.converter_options
    end

    # get the correct converter type
    def converter_factory
      case @options[:format]
      when "html" then HtmlConverter.new @paths, @deployment_info, @options
      when "pdf" then PdfConverter.new @paths, @deployment_info, @options
      else raise ArgumentoError, "Unknown conversion format: #{@options[:format]}"
      end
    end

    def add_success(adoc, adoc_stderr)
      @docinfo_store.add_success(adoc, adoc_stderr)
    end

    def add_fail(filepath, e)
      @docinfo_store.add_fail(filepath, e)
    end

    def setup_postprocessors(options)
      opts = {
        index_basename: @options[:indexBaseName],
        git_repo_root: @options[:gitRepoRoot]
      }
      @postprocessors.add_instance(IndexTreePostProcessor.new(opts)) unless options[:suppressBuildRef]
    end

    private

    # setup the deployment paths
    def setup_deployment_info
      # set the path to the search data that will be sent to the cgi search script
      deploy_search_path = if @options[:makeSearchable]
        if @options[:searchAssetsDeploy].nil?
          @paths.search_assets_abs
        else
          Pathname.new(@options[:searchAssetsDeploy]).join("search_assets")
        end
      end

      Giblish::DeploymentPaths.new(@options[:webPath], deploy_search_path)
    end

    # convert a single adoc doc to whatever the user wants
    def to_asciidoc(filepath)
      adoc_logger = Giblish::AsciidoctorLogger.new Logger::Severity::WARN
      adoc = @converter.convert(filepath, logger: adoc_logger)

      add_success(adoc, adoc_logger.user_info_str.string)
    rescue => e
      add_fail(filepath, e)
      raise
    end

    # predicate that decides if a path is a asciidoc file or not
    def adocfile?(path)
      fs = path.to_s
      unless @options[:excludeRegexp].nil?
        # exclude file if user wishes
        er = Regexp.new @options[:excludeRegexp]
        return false unless er.match(fs).nil?
      end

      # only include files matching the include regexp
      ir = Regexp.new @options[:includeRegexp]
      !ir.match(fs).nil?
    end

    def manage_searchability(opts)
      # create a data cache that will be used by the
      # header indexer
      @search_data_provider = SearchDataCache.new(
        file_set: @adoc_files,
        paths: @paths,
        id_prefix: (opts[:attributes].nil? ? nil : opts[:attributes].fetch("idprefix")),
        id_separator: (opts[:attributes].nil? ? nil : opts[:attributes].fetch("idseparator"))
      )

      # register the preprocessor hook that will index each heading
      # in the files that giblish processes
      HeadingIndexer.register
    end

    # Run the first pass necessary to collect all :docid: attributes found in document
    # headers and register the correct class as an asciidoctor extension that handles
    # all :docid: references
    def manage_doc_ids
      DocidCollector.run_pass1(adoc_files: @adoc_files)

      # Register the docid preprocessor hook
      Giblish.register_docid_extension
    end
  end

  # Converts all adoc files within a git repo
  class GitRepoConverter < FileTreeConverter
    def initialize(options)
      super(options)
      # cache the top of the tree since we need to redefine the
      # paths per branch/tag later on.
      @master_paths = @paths.dup
      @master_deployment_info = @deployment_info.dup
      @git_repo_root = options[:gitRepoRoot]
      @git_repo = init_git_repo @git_repo_root, options[:localRepoOnly]
      @user_branches = select_user_branches(options[:gitBranchRegexp])
      @user_tags = select_user_tags(options[:gitTagRegexp])
    end

    # Convert the docs from each branch/tag and add info to the
    # summary page.
    # return true if all conversions went ok, false if at least one
    # failed
    def convert
      conv_ok = (@user_branches + @user_tags).inject(true) do |memo, checkout|
        convert_one_checkout(checkout) && memo
      end

      # Render the summary page
      index_builder = GitSummaryIndexBuilder.new @git_repo, @user_branches, @user_tags
      summary_ok = @converter.convert_str(index_builder.source,
        @master_paths.dst_root_abs, "index")

      # clean up
      GC.start

      # return status
      conv_ok && summary_ok
    end

    protected

    def graph_builder_factory
      Giblish::GitGraphBuilderGraphviz.new @docinfo_store.doc_infos, @paths, @deployment_info,
        @converter.converter_options, @git_repo
    end

    def add_success(adoc, adoc_stderr)
      info = super(adoc, adoc_stderr)

      # Redefine the srcFile to mean the relative path to the git repo root
      src_file = Pathname.new(info.src_file).relative_path_from(@git_repo_root).to_s
      # Get the commit history of the doc
      # (use a homegrown git log to get 'follow' flag)
      gi = Giblish::GitItf.new(@git_repo_root)
      gi.file_log(src_file).each do |i|
        info.history << DocInfo::DocHistory.new(i["date"], i["author"], i["message"])
      end
    end

    private

    def init_git_repo(git_repo_root, local_only)
      # Sanity check git repo root
      git_repo_root || raise(ArgumentError("No git repo root dir given"))

      msg = "Could not find a git repo at #{git_repo_root} !"
      begin
        # Connect to the git repo
        git_repo = Git.open(git_repo_root)
        # fetch all remote refs if ok with user
        msg = "Could not fetch from origin (do you need '--local-only'?)!"
        git_repo.fetch unless local_only
      rescue => e
        raise "#{msg}\n\n#{e.message}"
      end
      git_repo
    end

    # Get the branches/tags the user wants to parse
    def select_user_branches(checkout_regexp)
      return unless @options[:gitBranchRegexp]

      regexp = Regexp.new checkout_regexp
      user_checkouts = @git_repo.branches.remote.select do |b|
        # match branches but remove eventual HEAD -> ... entry
        regexp.match b.name unless /^HEAD/.match?(b.name)
      end
      Giblog.logger.debug { "selected git branches: #{user_checkouts}" }
      user_checkouts
    end

    def select_user_tags(tag_regexp)
      return [] unless tag_regexp

      regexp = Regexp.new @options[:gitTagRegexp]
      @git_repo.tags.select do |t|
        regexp.match t.name
      end
    end

    # update necessary base class members to ensure correct conversion
    # of a specific checkout (branch or tag)
    # rubocop:disable Metrics/AbcSize
    def update_base_class_members(checkout)
      # assign a checkout-unique dst-dir
      dir_name = checkout.name.tr("/", "_") << "/"

      # Update needed base class members before converting a new checkout
      @paths.dst_root_abs = @master_paths.dst_root_abs.realpath.join(dir_name)
      @docinfo_store = DocInfoStore.new(@paths)
      # assemble the set of files that we shall process in this branch
      @adoc_files = CachedPathSet.new(@paths.src_root_abs, &method(:adocfile?)).paths

      if @options[:makeSearchable] && !@master_deployment_info.search_assets_path.nil?
        @paths.search_assets_abs = @master_paths.search_assets_abs.join(dir_name)
        @deployment_info.search_assets_path = @master_deployment_info.search_assets_path.join(dir_name)
        Giblog.logger.info { "will store search data in #{@paths.search_assets_abs}" }
      end
    end
    # rubocop:enable Metrics/AbcSize

    # convert all docs from one particular git commit
    # returns true if at least one doc failed to convert
    # and false if everything went ok.
    # rubocop:disable Metrics/AbcSize
    def convert_one_checkout(checkout)
      Giblog.logger.info { "Checking out #{checkout.name}" }
      @git_repo.checkout checkout.name

      # determine if we are called with a tag or a branch
      unless checkout.respond_to?(:tag?) && checkout.tag?
        # this is a branch, make sure it is up-to-date
        Giblog.logger.info { "Merging with origin/#{checkout.name}" }
        @git_repo.merge "origin/#{checkout.name}"
      end

      update_base_class_members(checkout)

      # Parse and convert docs using given args
      # by calling base class :convert
      Giblog.logger.info { "Convert docs into dir #{@paths.dst_root_abs}" }
      FileTreeConverter.instance_method(:convert).bind(self).call
    end
    # rubocop:enable Metrics/AbcSize
  end
end
