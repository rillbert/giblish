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

    def initialize(paths, deployment_info, options)
      @paths = paths
      @deployment_info = deployment_info
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
      add_doc_specific_attributes(filepath,true, @converter_options[:attributes])

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

      # give derived classes the opportunity to set doc specific attributes
      index_filepath = dst_dir + "#{basename}.#{index_opts[:fileext]}"
      add_doc_specific_attributes(index_filepath,false, index_opts[:attributes])

      # load and convert the document using the converter options
      doc = nil, output = nil

      begin
        conv_error = false
        # set a specific logger instance to-be-used by asciidoctor
        index_opts[:logger] = logger unless logger.nil?
        doc = Asciidoctor.load src_str, index_opts
        output = doc.convert index_opts

        if logger && logger.max_severity && logger.max_severity > Logger::Severity::WARN
          raise RuntimeError, "Failed to convert string to asciidoc!! Will _not_ generate #{index_filepath.to_s}"
        end

        # write the converted document to an index file located at the
        # destination root
        doc.write output, index_filepath.to_s
      rescue Exception => e
        Giblog.logger.error(e)
        conv_error = true
      end

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
    def add_doc_specific_attributes(filepath, is_src, attributes)

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
    def initialize(paths, deployment_info, options)
      super paths, deployment_info, options

      # validate that things are ok on the resource front
      # and copy if needed
      @dst_asset_dir = @paths.dst_root_abs.join("web_assets")
      validate_and_copy_resources @dst_asset_dir

      # identify ourselves as an html converter
      add_backend_options({backend: "html5", fileext: "html"})
      # setup the attributes specific for this converter
      add_backend_attributes(get_common_attributes)
    end

    protected

    def add_doc_specific_attributes(filepath, is_src_file, attributes)
      doc_attrib = {}
      if @paths.resource_dir_abs
        # user has given a resource dir, use the css from that dir
        doc_attrib.merge!(
            {
                "linkcss" => 1,
                "stylesheet" => @user_style ||= "giblish.css",
                "copycss!" => 1
            }
        )
        if @deployment_info.web_path.nil?
          # user wants to deploy without web server, the css
          # link shall thus be the relative path from the
          # generated doc to the css directory
          dst_css_dir = @dst_asset_dir.join("css")
          css_rel_dir = if is_src_file
                          # the filepath is a src path
                          @paths.relpath_to_dir_after_generate(
                              filepath,
                              dst_css_dir
                          )
                        else
                          # the given file path is the destination path of
                          # the generated file, find the relative path to the
                          # css dir
                          dst_dir = PathManager.closest_dir(filepath)
                          dst_css_dir.relative_path_from(dst_dir)
                        end
          doc_attrib["stylesdir"] = css_rel_dir.to_s
        else
          # user has given a web deployment path, the css shall then
          # be linked using that path
          doc_attrib["stylesdir"] = @deployment_info.web_path.join("css").cleanpath.to_s
        end
      end
        Giblog.logger.debug {"Rendered docs expect a css at: #{doc_attrib["stylesdir"]}"}
        Giblog.logger.debug {"The expected css is named: #{doc_attrib["stylesheet"]}"}

      attributes.merge!(doc_attrib)
    end

    private

    def get_common_attributes
      # Setting 'data-uri' makes asciidoctor embed images in the resulting
      # html file
      html_attrib = {
          "data-uri" => 1,
      }
      html_attrib
    end

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
  end

  class PdfConverter < DocConverter
    def initialize(paths, deployment_info, options)
      super paths, deployment_info, options

      # identify ourselves as a pdf converter
      add_backend_options({backend: "pdf", fileext: "pdf"})
      # setup the attributes specific for this converter
      add_backend_attributes(setup_pdf_attribs)
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
