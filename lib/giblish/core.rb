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

# Base class for document converters. It contains a hash of
# conversion options used by derived classes
class DocConverter
  # a common set of converter options used for all output formats
  COMMON_CONVERTER_OPTS = {
    safe: Asciidoctor::SafeMode::UNSAFE,
    header_footer: true,
    mkdirs: true
  }.freeze

  # setup common options that are used regardless of the
  # specific output format used
  attr_reader :converter_options

  # Public: Setup common converter options. Required options are:
  #         :srcDirRoot
  #         :dstDirRoot
  #         :resourceDir
  def initialize(options)
    @paths = Giblish::PathManager.new(
      options[:srcDirRoot], options[:dstDirRoot], options[:resourceDir]
    )

    @user_style = options[:userStyle]
    @converter_options = COMMON_CONVERTER_OPTS.dup
    @converter_options[:backend] = options[:backend]
  end

  def convert_str(input_str, src_path, output_file = nil)
    unless input_str.is_a?(String)
      raise ArgumentError("Trying to invoke convert_str with non-string!")
    end

    # use the same options as when converting all docs
    # in the tree but make sure Asciidoctor doesn't write to file
    index_opts = @converter_options.dup
    index_opts.delete(:to_file)
    index_opts.delete(:to_dir)

    # load and convert the string using the converter options
    doc = Asciidoctor.load input_str, index_opts
    output = doc.convert index_opts

    # determine the correct output path
    if output_file.nil?
      output_file = @paths.adoc_output_file(src_path,
                                            @converter_options[:fileext])
    end

    # write the converted document to file and return the doc
    doc.write output, output_file.to_s
    doc
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
    Giblish.register_extensions
    Asciidoctor.convert_file filepath, @converter_options
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
    @converter_options[:attributes] = backend_attribs
  end
end

# Converts asciidoc files to html5 output.
class HtmlConverter < DocConverter
  # Public: Setup common converter options. Required options are:
  #         :srcDirRoot
  #         :dstDirRoot
  #         :resourceDir
  def initialize(options)
    super options

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
  def initialize(options)
    super options

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

class TreeConverter

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

    # init_dst_root

    # prepare the index page if requested
    unless @options[:suppressBuildRef]
      @index_builder = if @options[:gitRepoRoot]
                         GitRepoIndexBuilder.new(@paths, options[:gitRepoRoot])
                       else
                         SimpleIndexBuilder.new(@paths)
                       end
    end

    @conversion =
      case options[:format]
      when "html" then HtmlConverter.new options
      when "pdf" then PdfConverter.new options
      else
        raise ArgumentError, "Unknown conversion format: #{options[:format]}"
      end
  end

  def generate_index(src_str, dst_dir)
    # use the same options as when converting all docs
    # in the tree but make sure we don't write to file
    index_opts = @conversion.converter_options.dup
    index_opts.delete(:to_file)
    index_opts.delete(:to_dir)

    # load and convert the document using the converter options
    doc = Asciidoctor.load src_str, index_opts
    output = doc.convert index_opts

    # write the converted document to an index file located at the
    # destination root
    index_filepath = dst_dir + "index.#{index_opts[:fileext]}"
    doc.write output, index_filepath.to_s
  end

  def to_asciidoc(filepath)
    adoc = nil
    begin
      # do the conversion and capture eventual errors that
      # the asciidoctor lib writes to stderr
      adoc_stderr = Giblish.with_captured_stderr do
        adoc = @conversion.convert filepath
      end

      # build the reference index if the user wants it
      @options[:suppressBuildRef] || @index_builder.add_doc(adoc, adoc_stderr)
    rescue Exception => e
      str = "Error when converting doc: #{e.message}\n"
      e.backtrace.each { |l| str << "#{l}\n" }
      Giblog.logger.error { str }
      @options[:suppressBuildRef] || @index_builder.add_doc_fail(filepath, e)
    end
  end

  def walk_dirs_with_docid
    # pass 1: collect all found doc ids
    collect_doc_ids

    # pas 2: substitute :docid: tags and convert resulting strings
    walk_dirs
    # Find.find(src_root_path) do |path|
    #   next unless adocfile? path
    #   processed_str = idc.substitute_ids_file(path)
    #
    #   adoc = nil
    #   begin
    #     # do the conversion and capture eventual errors that
    #     # the asciidoctor lib writes to stderr
    #     adoc_stderr = Giblish.with_captured_stderr do
    #       adoc = @conversion.convert_str processed_str, path
    #     end
    #
    #     # build the reference index if the user wants it
    #     @options[:suppressBuildRef] || @index_builder.add_doc(adoc, adoc_stderr)
    #   rescue Exception => e
    #     str = "Error when converting doc: #{e.message}\n"
    #     e.backtrace.each { |l| str << "#{l}\n" }
    #     Giblog.logger.error { str }
    #     @options[:suppressBuildRef] || @index_builder.add_doc_fail(filepath, e)
    #   end
    # end
  end

  def walk_dirs
    # traverse the src file tree and convert all files that ends with
    # .adoc or .ADOC
    Find.find(@paths.src_root_abs) do |path|
      p = Pathname.new(path)
      to_asciidoc(p) if adocfile? p
    end

    # check if we shall build index or not
    return if @options[:suppressBuildRef]

    # build a reference index
    generate_index @index_builder.index_source, @paths.dst_root_abs

    # clean up adoc resources
    @index_builder = nil
    GC.start
  end

  private

  def adocfile?(path)
    path.extname.casecmp(".ADOC").zero?
  end

  def collect_doc_ids
    # Make sure that no prior docid's are hangning around
    Giblish::DocidCollector.clear_cache
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

class GitRepoParser
  def initialize(options)
    @options = options
    @paths = Giblish::PathManager.new(
      @options[:srcDirRoot],
      @options[:dstDirRoot],
      @options[:resourceDir]
    )
    @git_repo_root = options[:gitRepoRoot]

    # Sanity check git repo root
    @git_repo_root || raise(ArgumentError("No git repo root dir given"))

    # Connect to the git repo
    begin
      @git_repo = Git.open(@git_repo_root)
    rescue Exception => e
      raise "Could not find a git repo at #{@git_repo_root} !"\
            "\n\n(#{e.message})"
    end

    # fetch all remote refs if ok with user
    begin
      @git_repo.fetch unless options[:localRepoOnly]
    rescue Exception => e
      raise "Could not fetch from origin"\
            "(do you need '--local-only'?)!\n\n(#{e.message})"
    end

    # initialize summary builder
    @index_builder = GitSummaryIndexBuilder.new @git_repo

    # Get the branches the user wants to parse
    if options[:gitBranchRegexp]
      regexp = Regexp.new options[:gitBranchRegexp]
      @user_branches = @git_repo.branches.remote.select do |b|
        # match branches but remove eventual HEAD -> ... entry
        regexp.match b.name unless b.name =~ /^HEAD/
      end
      Giblog.logger.debug { "selected git branches: #{@user_branches}" }

      # Render the docs from each branch and add info to the
      # summary page
      @user_branches.each do |b|
        render_one_branch b, @options
        @index_builder.add_branch b
      end
    end

    # Get the branches the user wants to parse
    if options[:gitTagRegexp]
      regexp = Regexp.new options[:gitTagRegexp]
      @user_tags = @git_repo.tags.select do |t|
        regexp.match t.name
      end

      # Render the docs from each branch and add info to the
      # summary page
      @user_tags.each do |t|
        render_one_branch t, @options, true
        @index_builder.add_tag t
      end
    end

    # Render the summary page
    tc = TreeConverter.new options
    tc.generate_index @index_builder.index_source, @paths.dst_root_abs

    # clean up
    @index_builder = nil
    GC.start
  end

  def render_one_branch(b, opts, is_tag = false)
    # work with local options
    options = opts.dup

    # check out the branch in question and make sure it is
    # up-to-date
    Giblog.logger.info { "Checking out #{b.name}" }
    @git_repo.checkout b.name

    unless is_tag
      Giblog.logger.info { "Merging with origin/#{b.name}" }
      @git_repo.merge "origin/#{b.name}"
    end

    # assign a branch-unique dst-dir
    dir_name = b.name.tr("/", "_") << "/"

    # Assign the branch specific dir as new destination root
    options[:dstDirRoot] = @paths.dst_root_abs.realpath.join(dir_name).to_s

    # Parse and render docs using given args
    Giblog.logger.info { "Render docs to dir #{options[:dstDirRoot]}" }
    tc = TreeConverter.new options
#    tc.walk_dirs
    tc.walk_dirs_with_docid
  end
end
