require "find"
require "fileutils"
require "logger"
require "pathname"

require_relative "buildindex"
require_relative "docconverter"
require_relative "docid"
require_relative "indexheadings"
require_relative "docinfo"
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

      @paths = Giblish::PathManager.new(
          @options[:srcDirRoot],
          @options[:dstDirRoot],
          @options[:resourceDir],
          @options[:webRoot]
      )
      @processed_docs = []
      @converter = converter_factory
      @search_assets_path = @paths.dst_root_abs.realpath.join("search_assets")
    end


    # convert all adoc files
    # return true if all conversions went ok, false if at least one
    # failed
    def convert
      # collect all doc ids and enable replacement of known doc ids with
      # valid references to adoc files
      manage_doc_ids if @options[:resolveDocid]

      # register add-on for handling searchability
      manage_searchability(@options) if @options[:make_searchable]

      # traverse the src file tree and convert all files deemed as
      # adoc files
      conv_error = false
      Find.find(@paths.src_root_abs) do |path|
        p = Pathname.new(path)
        begin
          to_asciidoc(p) if adocfile? p
        rescue Exception => e
          str = "Error when converting file #{path.to_s}: #{e.message}\nBacktrace:\n"
          e.backtrace.each {|l| str << "   #{l}\n"}
          Giblog.logger.error {str}
          conv_error = true
        end
      end if @paths.src_root_abs.directory?

      # create necessary search assets if needed
      create_search_assets if @options[:make_searchable]

      # build index and other fancy stuff if not suppressed
      unless @options[:suppressBuildRef]
        # build a dependency graph (only if we resolve docids...)
        dep_graph_exist = @options[:resolveDocid] && build_graph_page

        # build a reference index
        build_index_page(dep_graph_exist)
      end
      conv_error
    end

    protected

    def build_graph_page
      begin
        adoc_logger = Giblish::AsciidoctorLogger.new Logger::Severity::WARN
        gb = graph_builder_factory
        errors = @converter.convert_str(
            gb.source(
                @options[:make_searchable]
            ),
            @paths.dst_root_abs,
            "graph",
            logger: adoc_logger
        )
        gb.cleanup
        !errors
      rescue Exception => e
        Giblog.logger.warn { e.message }
        Giblog.logger.warn { "The dependency graph will not be generated !!" }
      end
      false
    end

    def build_index_page(dep_graph_exist)
      # build a reference index
      adoc_logger = Giblish::AsciidoctorLogger.new Logger::Severity::WARN
      ib = index_factory
      @converter.convert_str(
          ib.source(
              dep_graph_exist,@options[:make_searchable]
          ),
          @paths.dst_root_abs,
          @options[:indexBaseName],
          logger: adoc_logger
      )

      # clean up cached files and adoc resources
      GC.start
    end

    # get the correct index builder type depending on supplied
    # user options
    def index_factory
      raise "Internal logic error!" if @options[:suppressBuildRef]
      SimpleIndexBuilder.new(@processed_docs, @converter, @paths,
                             @options[:resolveDocid])
    end

    def graph_builder_factory
      Giblish::GraphBuilderGraphviz.new @processed_docs, @paths, @converter.converter_options
    end

    # get the correct converter type
    def converter_factory
      case @options[:format]
        when "html" then
          HtmlConverter.new @paths, @options
        when "pdf" then
          PdfConverter.new @paths, @options
        else
          raise ArgumentError, "Unknown conversion format: #{@options[:format]}"
      end
    end

    # creates a DocInfo instance, fills it with basic info and
    # returns the filled in instance so that derived implementations can
    # add more data
    def add_doc(adoc, adoc_stderr)
      Giblog.logger.debug do
        "Adding adoc: #{adoc} Asciidoctor stderr: #{adoc_stderr}"
      end
      Giblog.logger.debug {"Doc attributes: #{adoc.attributes}"}

      info = DocInfo.new(adoc: adoc, dst_root_abs: @paths.dst_root_abs, adoc_stderr: adoc_stderr)
      @processed_docs << info
      info
    end

    def add_doc_fail(filepath, exception)
      info = DocInfo.new

      # the only info we have is the source file name
      info.converted = false
      info.src_file = filepath.to_s
      info.error_msg = exception.message

      @processed_docs << info
      info
    end

    private

    def create_search_asset_dir
      Dir.exist?(@search_assets_path) || FileUtils.mkdir_p(@search_assets_path.to_s)
      @search_assets_path
    end

    # convert a single adoc doc to whatever the user wants
    def to_asciidoc(filepath)
      adoc = nil
      begin
        adoc_logger = Giblish::AsciidoctorLogger.new Logger::Severity::WARN
        adoc = @converter.convert(filepath,logger: adoc_logger)

        add_doc(adoc, adoc_logger.user_info_str.string)
      rescue Exception => e
        add_doc_fail(filepath, e)
        raise
      end
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
      return !ir.match(fs).nil?
    end

    def manage_searchability(opts)
      # register the extension
      Giblish.register_index_heading_extension

      # make sure we start from a clean slate
      IndexHeadings.clear_index

      # propagate user-given id attributes to the indexing class
      attr = opts[:attributes]
      if !attr.nil?
        if attr.has_key?("idprefix")
          IndexHeadings.id_elements[:id_prefix] = attr["idprefix"]
        end
        if attr.has_key?("idseparator")
          IndexHeadings.id_elements[:id_separator] = attr["idseparator"]
        end
      end
    end

    # top_dir
    # |- web_assets
    # |- branch_1_top_dir
    # |     |- index.html
    # |     |- file1.html
    # |     |- dir_1
    # |     |   |- file2.html
    # |- search_assets
    # |     |- branch_1
    # |           |- heading_index.json
    # |           |- file1.adoc
    # |           |- dir_1
    # |           |   |- file2.html
    # |           |- ...
    # |     |- branch_2
    # |           | ...
    # |- branch_2_top_dir
    # | ...
    def create_search_assets
      # get the proper dir for the search assets
      assets_dir = create_search_asset_dir

      # store the JSON file
      IndexHeadings.serialize assets_dir, @paths.src_root_abs

      # traverse the src file tree and copy all published adoc files
      # to the search_assets dir
      Find.find(@paths.src_root_abs) do |path|
        p = Pathname.new(path)
        next unless adocfile? p

        dst_dir = assets_dir.join(@paths.reldir_from_src_root(p))
        FileUtils.mkdir_p(dst_dir)
        FileUtils.cp(p.to_s, dst_dir)
      end if @paths.src_root_abs.directory?
    end

    # Register the asciidoctor extension that handles doc ids and traverse
    # the source tree to collect all :docid: attributes found in document
    # headers.
    def manage_doc_ids
      # Register the docid preprocessor hook
      Giblish.register_docid_extension

      # Make sure that no prior docid's are hangning around
      DocidCollector.clear_cache
      DocidCollector.clear_deps
      idc = DocidCollector.new

      # traverse the src file tree and collect ids from all
      # .adoc or .ADOC files
      Find.find(@paths.src_root_abs) do |path|
        p = Pathname.new(path)
        idc.parse_file(p) if adocfile? p
      end if @paths.src_root_abs.directory?
      idc
    end
  end

  class GitRepoConverter < FileTreeConverter
    def initialize(options)
      super(options)
      # cache the top of the tree since we need to redefine the
      # paths per branch/tag later on.
      @master_paths = @paths.dup
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
      conv_error = false
      (@user_branches + @user_tags).each do |co|
        conv_error = conv_error || convert_one_checkout(co)
      end

      # Render the summary page
      index_builder = GitSummaryIndexBuilder.new @git_repo,
                                                 @user_branches,
                                                 @user_tags

      conv_error = conv_error || @converter.convert_str(
          index_builder.source,
          @master_paths.dst_root_abs,
          "index"
      )

      # clean up
      GC.start

      conv_error
    end

    protected

    def index_factory
      GitRepoIndexBuilder.new(@processed_docs, @converter, @paths,
                              @options[:resolveDocid], @options[:gitRepoRoot])
    end

    def graph_builder_factory
      Giblish::GitGraphBuilderGraphviz.new @processed_docs, @paths, @converter.converter_options,@git_repo
    end

    def add_doc(adoc, adoc_stderr)
      info = super(adoc, adoc_stderr)

      # Redefine the srcFile to mean the relative path to the git repo root
      src_file = Pathname.new(info.src_file).relative_path_from(@git_repo_root).to_s
      # Get the commit history of the doc
      # (use a homegrown git log to get 'follow' flag)
      gi = Giblish::GitItf.new(@git_repo_root)
      gi.file_log(src_file).each do |i|
        h = DocInfo::DocHistory.new
        h.date = i["date"]
        h.message = i["message"]
        h.author = i["author"]
        info.history << h
      end
    end

    private

    def init_git_repo(git_repo_root, local_only)
      # Sanity check git repo root
      git_repo_root || raise(ArgumentError("No git repo root dir given"))

      # Connect to the git repo
      begin
        git_repo = Git.open(git_repo_root)
      rescue Exception => e
        raise "Could not find a git repo at #{git_repo_root} !"\
            "\n\n(#{e.message})"
      end

      # fetch all remote refs if ok with user
      begin
        git_repo.fetch unless local_only
      rescue Exception => e
        raise "Could not fetch from origin"\
            "(do you need '--local-only'?)!\n\n(#{e.message})"
      end
      git_repo
    end

    # Get the branches/tags the user wants to parse
    def select_user_branches(checkout_regexp)
      return unless @options[:gitBranchRegexp]

      regexp = Regexp.new checkout_regexp
      user_checkouts = @git_repo.branches.remote.select do |b|
        # match branches but remove eventual HEAD -> ... entry
        regexp.match b.name unless b.name =~ /^HEAD/
      end
      Giblog.logger.debug {"selected git branches: #{user_checkouts}"}
      user_checkouts
    end

    def select_user_tags(tag_regexp)
      return [] unless tag_regexp

      regexp = Regexp.new @options[:gitTagRegexp]
      tags = @git_repo.tags.select do |t|
        regexp.match t.name
      end
      tags
    end

    # convert all docs from one particular git commit
    # returns true if at least one doc failed to convert
    # and false if everything went ok.
    def convert_one_checkout(co)
      # determine if we are called with a tag or a branch
      is_tag = (co.respond_to?(:tag?) && co.tag?)

      Giblog.logger.info {"Checking out #{co.name}"}
      @git_repo.checkout co.name

      unless is_tag
        # if this is a branch, make sure it is up-to-date
        Giblog.logger.info {"Merging with origin/#{co.name}"}
        @git_repo.merge "origin/#{co.name}"
      end

      # assign a checkout-unique dst-dir
      dir_name = co.name.tr("/", "_") << "/"

      # Update needed base class members before converting a new checkout
      @processed_docs = []
      @paths.dst_root_abs = @master_paths.dst_root_abs.realpath.join(dir_name)
      @search_assets_path = @master_paths.dst_root_abs.realpath.join("search_assets").join(dir_name)

      # Parse and convert docs using given args
      Giblog.logger.info {"Convert docs into dir #{@paths.dst_root_abs}"}
      # parent_convert
      FileTreeConverter.instance_method(:convert).bind(self).call
    end
  end
end