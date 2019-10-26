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
      @paths = paths
      @user_style = options[:userStyle]
      @converter_options = COMMON_CONVERTER_OPTS.dup

      # use the default options and override them with options set by
      # the user if applicable
      @converter_options[:attributes] = DEFAULT_ATTRIBUTES.dup
      @converter_options[:attributes].merge!(options[:attributes]) unless options[:attributes].nil?
      @converter_options[:backend] = options[:backend]

      # give derived classes the opportunity to add options and attributes
      add_backend_options(@converter_options)
      add_backend_attributes(@converter_options[:attributes])
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

      # update the relevant options for each specific document
      set_common_doc_specific_options(filepath,logger)

      # give derived classes the opportunity to set doc specific attributes
      add_doc_specific_attributes(filepath,@converter_options[:attributes])

      Giblog.logger.info "attributes: #{@converter_options[:attributes]}"

      Giblog.logger.debug {"converter_options: #{@converter_options}"}

      # do the actual conversion
      doc = Asciidoctor.convert_file filepath, @converter_options

      # bail out if asciidoctor failed to convert the doc
      if logger && logger.max_severity && logger.max_severity > Logger::Severity::WARN
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
    # Returns: whether any errors occured during conversion (true) or
    # not (false).
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

      begin
        conv_error = false
        # set a specific logger instance to-be-used by asciidoctor
        index_opts[:logger] = logger unless logger.nil?
        doc = Asciidoctor.load src_str, index_opts
        output = doc.convert index_opts

        index_filepath = dst_dir + "#{basename}.#{index_opts[:fileext]}"

        if logger && logger.max_severity && logger.max_severity > Logger::Severity::WARN
          raise RuntimeError, "Failed to convert string to asciidoc!! Will _not_ generate #{index_filepath.to_s}"
        end
      rescue Exception => e
        Giblog.logger.error(e)
        conv_error = true
      end


      # write the converted document to an index file located at the
      # destination root
      doc.write output, index_filepath.to_s
      conv_error
    end

    protected

    # Hook for specific converters to inject their own options.
    # The following options must be provided by the derived class:
    #   :fileext - a string with the filename extention to use for the
    #              generated file
    #
    # backend_options - the option dict from the backend implementation
    def add_backend_options(backend_options)
      @converter_options.merge!(backend_options)
    end

    # Hook for specific converters to inject their own attributes
    # valid for all conversions.
    # backend_attributes - the attribute dict from the backend implementation
    def add_backend_attributes(backend_attributes)
      @converter_options[:attributes].merge!(backend_attributes)
    end

    # Hook for specific converters to inject attributes on a per-doc
    # basis
    def add_doc_specific_attributes(src_filepath, attributes)

    end

    private

    def set_common_doc_specific_options(src_filepath,logger)
      # create an asciidoc doc object and convert to requested
      # output using current conversion options
      @converter_options[:to_dir] = @paths.adoc_output_dir(src_filepath).to_s
      @converter_options[:base_dir] =
          Giblish::PathManager.closest_dir(src_filepath).to_s
      @converter_options[:to_file] =
          Giblish::PathManager.get_new_basename(src_filepath,
                                                @converter_options[:fileext])
      @converter_options[:logger] = logger unless logger.nil?
    end
  end

  # Converts asciidoc files to html5 output.
  class HtmlConverter < DocConverter
    def initialize(paths, options)
      super paths, options

      # validate that things are ok on the resource front
      # and copy if needed
      @dst_asset_dir = @paths.dst_root_abs.join("web_assets")
      validate_and_copy_resources @dst_asset_dir

      # convenience path to css dir
      @dst_css_dir = @dst_asset_dir.join("css")

      # identify ourselves as an html converter
      add_backend_options({backend: "html5", fileext: "html"})
      # setup the attributes specific for this converter
      add_backend_attributes(get_common_attributes)
    end

    protected

    def get_common_attributes
      # Setting 'data-uri' makes asciidoctor embed images in the resulting
      # html file
      html_attrib = {
          "data-uri" => 1,
      }

      if @paths.resource_dir_abs
        # user wants to use own styling, set common attributes
        html_attrib.merge!(
            {
                "linkcss" => 1,
                "stylesheet" => @user_style ||= "giblish.css",
                "copycss!" => 1
            }
        )

        # check if user wants to use a web root path
        @web_root = @paths.web_root_abs

        if @web_root
          # if user requested a web root to be used, the correct
          # css link is the relative path from the web root to the
          # css file. This is true for all documents
          wr_rel = @dst_css_dir.relative_path_from @web_root
          Giblog.logger.info {"Relative web root: #{wr_rel}"}
          html_attrib["stylesdir"] = "/" << wr_rel.to_s
        end
      end
      html_attrib
    end

    def add_doc_specific_attributes(src_filepath, attributes)

      doc_attributes = {}
      if @paths.resource_dir_abs and not @web_root
        # user wants to use own styling without use of a
        # web root. the correct css link is the relative path
        # from the specific doc to the common css directory
        css_rel_dir = @paths.relpath_to_dir_after_generate(
            src_filepath,
            @dst_css_dir
        )
        doc_attributes["stylesdir"] = css_rel_dir.to_s
      end

      attributes.merge!(doc_attributes)
    end

    private

    def copy_resource_dir(dst_dir)
      # create assets_dir and copy everything in the resource dir
      # to the destination
      Dir.exist?(dst_dir) || FileUtils.mkdir_p(dst_dir)

      # copy all subdirs that exist in the source tree to the
      # dst tree
      %i[css fonts images].each do |dir|
        src = "#{@paths.resource_dir_abs}/#{dir}"
        Dir.exist?(src) && FileUtils.copy_entry(src, "#{dst_dir}/#{dir}")
      end
    end

    # make as sure as we can that the user has given a
    # directory with valid resources
    def validate_and_copy_resources(dst_dir)
      # we don't have a resource path, which is fine, use
      # defaults
      return nil unless @paths.resource_dir_abs

      # If user has requested the use of a specific css, use that,
      # otherwise use asciidoctor default css
      if @user_style
        # Make sure that a user supplied stylesheet ends with .css or .CSS
        @user_style && @user_style =
            /\.(css|CSS)$/ =~ @user_style ? @user_style : "#{@user_style}.css"

        # bail out if we can not find the given css file
        src_css_path = @paths.resource_dir_abs.
            join("css").join(Pathname.new(@user_style))
        raise RuntimeError, "Could not find the specified " +
            "css file at: #{src_css_path}" unless src_css_path.exist?
      end

      copy_resource_dir dst_dir
    end

    # asset link cases:
    # 1. src and destination (no git repo)
    # 2. resource dir, src and destination (no git repo)
    # 2. git branch, src and destination
    # 3.
    # source doc at:
    # rendered doc at:  /var/www/html/docs/testdocs
    # webroot: /var/www/html
    # css link: href="/docs/testdocs/web_assets/css/vironova.css
    #
    # Return the path used in the html doc to find the css.
    #
    # 1. In the case of publishing to a web server (using -w)
    # this path is relative to the DirectoryRoot but starting
    # with a slash (eg. /website_1/web_assets)
    # 2. In the case of publishing without a web server
    # this path is relative to the repository root
    # (eg ../../web_assets)    def set_backend_specific_attributes(src_filepath, attributes)
    # def setup_stylesheet_attributes(css_dir)
    #   return {} if @paths.resource_dir_abs.nil?
    #
    #   # use the supplied stylesheet if there is one
    #   attrib = {"linkcss" => 1,
    #             "stylesdir" => css_dir,
    #             "stylesheet" => "giblish.css",
    #             "copycss!" => 1}
    #
    #   Giblog.logger.debug {"stylesheet attributes: #{attrib}"}
    #   attrib
    # end
    #
    # # make sure that linked assets are available at dst_root
    # def setup_web_assets(html_dir_root = nil)
    #
    #   # only set this up if user has specified a resource dir
    #   return {} unless dst_asset_dir
    #
    #   unless html_dir_root
    #     # link the css relative to the asset dir at the destination
    #
    #   end
    #   # find the path to the assets dir that is correct when called from a url,
    #   # taking the DirectoryRoot for the web site into consideration.
    #   if html_dir_root
    #     wr = dst_asset_dir.relative_path_from Pathname.new(html_dir_root)
    #     Giblog.logger.info {"Relative web root: #{wr}"}
    #     assets_dir = "/" << wr.to_s
    #   end
    #
    #   Giblog.logger.info {"stylesheet dir: #{assets_dir}"}
    #   setup_stylesheet_attributes "#{assets_dir}/css"
    # end
  end

  class PdfConverter < DocConverter
    def initialize(paths, options)
      super paths, options
    end

    protected

    def add_backend_options(options)
      # identify ourselves as a pdf converter
      options.merge!({backend: "pdf", fileext: "pdf"})
    end

    def add_backend_attributes(attributes)
      # add attributes for styling
      attributes.merge!(setup_pdf_attribs)
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
