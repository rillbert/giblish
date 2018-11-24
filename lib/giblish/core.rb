require "find"
require "fileutils"
require "logger"
require "pathname"

require_relative "buildindex"
require_relative "docconverter"
require_relative "docid"
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
          @options[:resourceDir]
      )
      @processed_docs = []
      @converter = converter_factory
    end

    def convert
      # collect all doc ids and enable replacement of known doc ids with
      # valid references to adoc files
      manage_doc_ids if @options[:resolveDocid]

      # traverse the src file tree and convert all files deemed as
      # adoc files
      Find.find(@paths.src_root_abs) do |path|
        p = Pathname.new(path)
        to_asciidoc(p) if adocfile? p
      end

      # check if we shall build index or not
      return if @options[:suppressBuildRef]

      # build a dependency graph
      gb = Giblish::GraphBuilderGraphviz.new @processed_docs, @paths, {extension: @converter.converter_options[:fileext]}
      ok = @converter.convert_str gb.source, @paths.dst_root_abs, "graph"

      # build a reference index
      ib = index_factory
      @converter.convert_str ib.source(ok), @paths.dst_root_abs, "index"

      # clean up cached files and adoc resources
      # remove_diagram_temps if ok
      GC.start
    end

    protected

    # get the correct index builder type depending on supplied
    # user options
    def index_factory
      raise "Internal logic error!" if @options[:suppressBuildRef]
      SimpleIndexBuilder.new(@processed_docs, @paths,
                             @options[:resolveDocid])
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
      info.src_file = filepath
      info.error_msg = exception.message

      @processed_docs << info
      info
    end

    private

    # remove cache dir and svg image created by asciidoctor-diagram
    # when creating the document dependency graph
    def remove_diagram_temps
      adoc_diag_cache = @paths.dst_root_abs.join(".asciidoctor")
      FileUtils.remove_dir(adoc_diag_cache) if adoc_diag_cache.directory?
      Giblog.logger.info {"Removing cached files at: #{@paths.dst_root_abs.join("docdeps.svg").to_s}"}
      @paths.dst_root_abs.join("docdeps.svg").delete
    end

    # convert a single adoc doc to whatever the user wants
    def to_asciidoc(filepath)
      adoc = nil
      begin
        # do the conversion and capture eventual errors that
        # the asciidoctor lib writes to stderr
        adoc_stderr = Giblish.with_captured_stderr do
          adoc = @converter.convert filepath
        end

        add_doc(adoc, adoc_stderr)
      rescue Exception => e
        str = "Error when converting doc: #{e.message}\n"
        e.backtrace.each {|l| str << "#{l}\n"}
        Giblog.logger.error {str}

        add_doc_fail(filepath, e)
      end
    end

    # predicate that decides if a path is a asciidoc file or not
    def adocfile?(path)
      fs = path.basename.to_s

      unless @options[:excludeRegexp].nil?
        # exclude file if user wishes
        er = Regexp.new @options[:excludeRegexp]
        return false unless er.match(fs).nil?
      end

      # only include files
      ir = Regexp.new @options[:includeRegexp]
      return !ir.match(fs).nil?
    end

    # Register the asciidoctor extension that handles doc ids and traverse
    # the source tree to collect all :docid: attributes found in document
    # headers.
    def manage_doc_ids
      # Register the docid preprocessor hook
      Giblish.register_extensions

      # Make sure that no prior docid's are hangning around
      DocidCollector.clear_cache
      DocidCollector.clear_deps
      idc = DocidCollector.new

      # traverse the src file tree and collect ids from all
      # .adoc or .ADOC files
      Find.find(@paths.src_root_abs) do |path|
        p = Pathname.new(path)
        idc.parse_file(p) if adocfile? p
      end
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

    # Render the docs from each branch/tag and add info to the
    # summary page
    def convert
      (@user_branches + @user_tags).each do |co|
        convert_one_checkout co
      end

      # Render the summary page
      index_builder = GitSummaryIndexBuilder.new @git_repo,
                                                 @user_branches,
                                                 @user_tags
      @converter.convert_str index_builder.source, @master_paths.dst_root_abs, "index"
      # clean up
      GC.start
    end

    protected

    def index_factory
      GitRepoIndexBuilder.new(@processed_docs, @paths,
                              @options[:resolveDocid], @options[:gitRepoRoot])
    end

    def add_doc(adoc, adoc_stderr)
      info = super(adoc, adoc_stderr)

      # Get the commit history of the doc
      # (use a homegrown git log to get 'follow' flag)
      gi = Giblish::GitItf.new(@git_repo_root)
      gi.file_log(info.src_file.to_s).each do |i|
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

    def convert_one_checkout(co)
      # determine if we are called with a tag or a branch
      is_tag = (co.respond_to?(:tag?) && co.tag?)

      Giblog.logger.info {"Checking out #{co.name}"}
      @git_repo.checkout co.name

      unless is_tag
        # if this is a branch, make sure it is up-to-date
        Giblog.logger.debug {"Merging with origin/#{co.name}"}
        @git_repo.merge "origin/#{co.name}"
      end

      # assign a checkout-unique dst-dir
      dir_name = co.name.tr("/", "_") << "/"

      # Update needed base class members before converting a new checkout
      @processed_docs = []
      @paths.dst_root_abs = @master_paths.dst_root_abs.realpath.join(dir_name)
      # @converter.paths = @paths

      # Parse and convert docs using given args
      Giblog.logger.info {"Convert docs into dir #{@paths.dst_root_abs}"}
      # parent_convert
      FileTreeConverter.instance_method(:convert).bind(self).call
    end
  end
end