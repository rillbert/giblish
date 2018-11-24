#!/usr/bin/env ruby
#
# Converts a tree of asciidoc docs to pdf/html
#
#

require "find"
require "fileutils"
require "logger"
require "pathname"
require "asciidoctor"
require "asciidoctor-pdf"

require_relative "cmdline"
require_relative "buildindex"
require_relative "docid"
require_relative "docinfo"
require_relative "buildgraph"

# Base class for document converters. It contains a hash of
# conversion options used by derived classes
class DocConverter
  # a common set of converter options used for all output formats
  COMMON_CONVERTER_OPTS = {
    safe: Asciidoctor::SafeMode::UNSAFE,
    header_footer: true,
    mkdirs: true
  }.freeze

  # the giblish attribute defaults used if nothing else
  # is required by the user
  DEFAULT_ATTRIBUTES = {
    "source-highlighter" => "rouge",
    "xrefstyle" => "short"
  }.freeze

  # setup common options that are used regardless of the
  # specific output format used
  attr_reader :converter_options

  # the path manager used by this converter
  attr_accessor :paths

  def initialize(paths, options)
    @paths = paths
    @user_style = options[:userStyle]
    @converter_options = COMMON_CONVERTER_OPTS.dup
    @converter_options[:attributes] = DEFAULT_ATTRIBUTES.dup
    @converter_options[:backend] = options[:backend]
  end

  # Public: Convert one single adoc file using the specific conversion
  # options.
  #
  # filepath - a pathname with the absolute path to the input file to convert
  #
  # Returns: The resulting Asciidoctor::Document object
  def convert(filepath)
    unless filepath.is_a?(Pathname)
      raise ArgumentError, "Trying to invoke convert with non-pathname!"
    end

    Giblog.logger.info { "Processing: #{filepath}" }

    # create an asciidoc doc object and convert to requested
    # output using current conversion options
    @converter_options[:to_dir] = @paths.adoc_output_dir(filepath).to_s
    @converter_options[:base_dir] =
      Giblish::PathManager.closest_dir(filepath).to_s
    @converter_options[:to_file] =
      Giblish::PathManager.get_new_basename(filepath,
                                            @converter_options[:fileext])

    Giblog.logger.debug { "converter_options: #{@converter_options}" }
    # do the actual conversion

    Asciidoctor.convert_file filepath, @converter_options
  end

  # converts the supplied string to the file
  # dst_dir/basename.<backend-ext>
  #
  # the supplied string must pass asciidoctor without
  # any error to stderr, otherwise, nothing will be written
  # to disk.
  # returns 'true' if a file was written, 'false' if not
  def convert_str(src_str, dst_dir, basename)
    index_opts = @converter_options.dup

    # use the same options as when converting all docs
    # in the tree but make sure we don't write to file
    # by trial and error, the following dirs seem to be
    # necessary to change
    index_opts[:to_dir] = dst_dir.to_s
    index_opts[:base_dir] = dst_dir.to_s
    index_opts.delete_if { |k, _v| %i[to_file].include? k }

    # load and convert the document using the converter options
    doc = nil, output = nil
    adoc_stderr = Giblish.with_captured_stderr do
      doc = Asciidoctor.load src_str, index_opts
      output = doc.convert index_opts
    end

    # if we get anything from asciidoctor to stderr,
    # consider this a failure and do not emit a file.
    return false unless adoc_stderr.length.zero?

    # write the converted document to an index file located at the
    # destination root
    index_filepath = dst_dir + "#{basename}.#{index_opts[:fileext]}"
    doc.write output, index_filepath.to_s
    true
  end

  protected

  # Protected: Adds the supplied backend specific options and
  #            attributes to the base ones.
  #            The following options must be provided by the derived class:
  #            :fileext - a string with the filename extention to use for the
  #                       generated file
  #
  # backend_opts - the options specific to the asciidoctor backend
  #                that the derived class supports
  # backend_attribs - the attributes specific to the asciidoctor backend
  #                   that the derived class supports
  def add_backend_options(backend_opts, backend_attribs)
    @converter_options = @converter_options.merge(backend_opts)
    @converter_options[:attributes] =
      @converter_options[:attributes].merge(backend_attribs)
  end
end

# Converts asciidoc files to html5 output.
class HtmlConverter < DocConverter
  def initialize(paths, options)
    super paths, options

    # require access to asciidoc-rouge
    require "asciidoctor-rouge"

    require "asciidoctor-diagram"

    # handle needed assets for the styling (css et al)
    html_attrib = setup_web_assets options[:webRoot]

    # Setting 'data-uri' makes asciidoctor embed images in the resulting
    # html file
    html_attrib["data-uri"] = 1

    # tell asciidoctor to use the html5 backend
    backend_options = { backend: "html5", fileext: "html" }
    add_backend_options backend_options, html_attrib
  end

  private

  def setup_stylesheet_attributes(css_dir)
    return {} if @paths.resource_dir_abs.nil?

    # use the supplied stylesheet if there is one
    attrib = { "linkcss" => 1,
               "stylesdir" => css_dir,
               "stylesheet" => "giblish.css",
               "copycss!" => 1 }

    # Make sure that a user supplied stylesheet ends with .css or .CSS
    @user_style &&
      attrib["stylesheet"] =
        /\.(css|CSS)$/ =~ @user_style ? @user_style : "#{@user_style}.css"
    Giblog.logger.debug {"stylesheet attributes: #{attrib}"}
    attrib
  end

  # make sure that linked assets are available at dst_root
  def setup_web_assets(html_dir_root = nil)
    # only set this up if user has specified a resource dir
    return {} unless @paths.resource_dir_abs

    # create dir for web assets directly under dst_root
    assets_dir = "#{@paths.dst_root_abs}/web_assets"
    Dir.exist?(assets_dir) || FileUtils.mkdir_p(assets_dir)

    # copy needed assets
    %i[css fonts images].each do |dir|
      src = "#{@paths.resource_dir_abs}/#{dir}"
      Dir.exist?(src) && FileUtils.copy_entry(src, "#{assets_dir}/#{dir}")
    end

    # find the path to the assets dir that is correct when called from a url,
    # taking the DirectoryRoot for the web site into consideration.
    if html_dir_root
      wr = Pathname.new(
        assets_dir
      ).relative_path_from Pathname.new(html_dir_root)
      Giblog.logger.info { "Relative web root: #{wr}" }
      assets_dir = "/" << wr.to_s
    end

    Giblog.logger.info { "stylesheet dir: #{assets_dir}" }
    setup_stylesheet_attributes "#{assets_dir}/css"
  end
end

class PdfConverter < DocConverter
  def initialize(paths, options)
    super paths, options

    pdf_attrib = setup_pdf_attribs

    backend_options = { backend: "pdf", fileext: "pdf" }
    add_backend_options backend_options, pdf_attrib
  end

  private

  def setup_pdf_attribs()
    # only set this up if user has specified a resource dir
    return {} unless @paths.resource_dir_abs

    pdf_attrib = {
      "pdf-stylesdir" => "#{@paths.resource_dir_abs}/themes",
      "pdf-style" => "giblish.yml",
      "pdf-fontsdir" => "#{@paths.resource_dir_abs}/fonts",
      "icons" => "font"
    }

    # Make sure that the stylesheet ends with .yml or YML
    @user_style &&
      pdf_attrib["pdf-style"] =
        /\.(yml|YML)$/ =~ @user_style ? @user_style : "#{@user_style}.yml"

    pdf_attrib
  end
end

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

    # traverse the src file tree and convert all files that ends with
    # .adoc or .ADOC
    Find.find(@paths.src_root_abs) do |path|
      p = Pathname.new(path)
      to_asciidoc(p) if adocfile? p
    end

    # check if we shall build index or not
    return if @options[:suppressBuildRef]

    # build a dependency graph
    gb = Giblish::GraphBuilderGraphviz.new @processed_docs, @paths
    ok = @converter.convert_str gb.source, @paths.dst_root_abs, "graph"

    # build a reference index
    ib = index_factory
    @converter.convert_str ib.source(ok), @paths.dst_root_abs, "index"

    # clean up cached files and adoc resources
    remove_diagram_temps
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
    when "html" then HtmlConverter.new @paths, @options
    when "pdf" then PdfConverter.new @paths, @options
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
    Giblog.logger.debug { "Doc attributes: #{adoc.attributes}" }

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

  # remove cache dir and svg image created by asciidoctor-Diagram
  # when creating the document dependency graph
  def remove_diagram_temps
    adoc_diag_cache = @paths.dst_root_abs.join(".asciidoctor")
    FileUtils.remove_dir(adoc_diag_cache) if adoc_diag_cache.directory?
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
      e.backtrace.each { |l| str << "#{l}\n" }
      Giblog.logger.error { str }

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
    Giblish::DocidCollector.clear_cache
    Giblish::DocidCollector.clear_deps
    idc = Giblish::DocidCollector.new

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
    Giblog.logger.debug { "selected git branches: #{user_checkouts}" }
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

    Giblog.logger.info { "Checking out #{co.name}" }
    @git_repo.checkout co.name

    unless is_tag
      # if this is a branch, make sure it is up-to-date
      Giblog.logger.debug { "Merging with origin/#{co.name}" }
      @git_repo.merge "origin/#{co.name}"
    end

    # assign a checkout-unique dst-dir
    dir_name = co.name.tr("/", "_") << "/"

    # Update needed base class members before converting a new checkout
    @processed_docs = []
    @paths.dst_root_abs = @master_paths.dst_root_abs.realpath.join(dir_name)
    # @converter.paths = @paths

    # Parse and convert docs using given args
    Giblog.logger.info { "Convert docs into dir #{@paths.dst_root_abs}" }
    # parent_convert
    FileTreeConverter.instance_method(:convert).bind(self).call
  end
end
