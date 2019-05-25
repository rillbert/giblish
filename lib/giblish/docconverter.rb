require "pathname"
require "asciidoctor"
require "asciidoctor-pdf"

require_relative "utils"

module Giblish

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
      # access the source highlight module
      require "asciidoctor-rouge"

      @paths = paths
      @user_style = options[:userStyle]
      @converter_options = COMMON_CONVERTER_OPTS.dup

      # use the default options and override them with options set by
      # the user if applicable
      @converter_options[:attributes] = DEFAULT_ATTRIBUTES.dup
      @converter_options[:attributes].merge!(options[:attributes]) unless options[:attributes].nil?

      @converter_options[:backend] = options[:backend]
    end

    # Public: Convert one single adoc file using the specific conversion
    # options.
    #
    # filepath - a pathname with the absolute path to the input file to convert
    #
    # Returns: The resulting Asciidoctor::Document object
    def convert(filepath, logger: nil)
      unless filepath.is_a?(Pathname)
        raise ArgumentError, "Trying to invoke convert with non-pathname!"
      end

      Giblog.logger.info {"Processing: #{filepath}"}

      # create an asciidoc doc object and convert to requested
      # output using current conversion options
      @converter_options[:to_dir] = @paths.adoc_output_dir(filepath).to_s
      @converter_options[:base_dir] =
          Giblish::PathManager.closest_dir(filepath).to_s
      @converter_options[:to_file] =
          Giblish::PathManager.get_new_basename(filepath,
                                                @converter_options[:fileext])

      # set a specific logger instance to-be-used by asciidoctor
      @converter_options[:logger] = logger unless logger.nil?

      Giblog.logger.debug {"converter_options: #{@converter_options}"}

      # do the actual conversion
      doc = Asciidoctor.convert_file filepath, @converter_options

      if logger && logger.max_severity && logger.max_severity >= Logger::Severity::WARN
        raise RuntimeError, "Failed to convert the file #{filepath}"
      end
      doc
    end

    # converts the supplied string to the file
    # dst_dir/basename.<backend-ext>
    #
    # the supplied string must pass asciidoctor without
    # any error to stderr, otherwise, nothing will be written
    # to disk.
    # returns 'true' if a file was written, 'false' if not
    def convert_str(src_str, dst_dir, basename,logger: nil)
      index_opts = @converter_options.dup

      # use the same options as when converting all docs
      # in the tree but make sure we don't write to file
      # by trial and error, the following dirs seem to be
      # necessary to change
      index_opts[:to_dir] = dst_dir.to_s
      index_opts[:base_dir] = dst_dir.to_s
      index_opts.delete_if {|k, _v| %i[to_file].include? k}

      # load and convert the document using the converter options
      doc = nil, output = nil

      # set a specific logger instance to-be-used by asciidoctor
      index_opts[:logger] = logger unless logger.nil?
      doc = Asciidoctor.load src_str, index_opts
      output = doc.convert index_opts

      index_filepath = dst_dir + "#{basename}.#{index_opts[:fileext]}"

      if logger && logger.max_severity && logger.max_severity >= Logger::Severity::WARN
        raise RuntimeError, "Failed to convert string to asciidoc!! Will _not_ generate #{index_filepath.to_s}"
      end

      # write the converted document to an index file located at the
      # destination root
      doc.write output, index_filepath.to_s
      0
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

      # handle needed assets for the styling (css et al)
      html_attrib = setup_web_assets options[:webRoot]

      # Setting 'data-uri' makes asciidoctor embed images in the resulting
      # html file
      html_attrib["data-uri"] = 1

      # tell asciidoctor to use the html5 backend
      backend_options = {backend: "html5", fileext: "html"}
      add_backend_options backend_options, html_attrib
    end

    private

    def setup_stylesheet_attributes(css_dir)
      return {} if @paths.resource_dir_abs.nil?

      # use the supplied stylesheet if there is one
      attrib = {"linkcss" => 1,
                "stylesdir" => css_dir,
                "stylesheet" => "giblish.css",
                "copycss!" => 1}

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
        Giblog.logger.info {"Relative web root: #{wr}"}
        assets_dir = "/" << wr.to_s
      end

      Giblog.logger.info {"stylesheet dir: #{assets_dir}"}
      setup_stylesheet_attributes "#{assets_dir}/css"
    end
  end

  class PdfConverter < DocConverter
    def initialize(paths, options)
      super paths, options

      pdf_attrib = setup_pdf_attribs

      backend_options = {backend: "pdf", fileext: "pdf"}
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
end
