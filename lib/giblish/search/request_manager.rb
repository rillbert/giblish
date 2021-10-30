require_relative "textsearcher"

module Giblish
  class DefaultHtmlGenerator
    # search_result:: a hash conforming to the output of
    #                 the TextSearcher::search method.
    # returns::       a string with the html to return to the client
    def response(search_result, css_path = nil)
      adoc_2_html(search_2_adoc(search_result), css_path)
    end

    private

    def adoc_2_html(adoc_source, css_path = nil)
      # setup default document attributes used in the html conversion
      doc_attr = css_path ? {
        "stylesdir" => css_path.dirname.to_s,
        "stylesheet" => css_path.basename.to_s,
        "linkcss" => true,
        "copycss" => nil
      } : {}
      doc_attr["data-uri"] = 1
      doc_attr["example-caption"] = nil

      # setup default conversion options
      converter_options = {
        backend: "html5",
        # need this to let asciidoctor include the default css if user
        # has not specified any css
        safe: Asciidoctor::SafeMode::SAFE,
        header_footer: true,
        attributes: doc_attr
      }

      # for debugging of adoc source
      # File.write("search.adoc", adoc_source)

      # convert to html and return result
      Asciidoctor.convert(adoc_source, converter_options)
    end

    # search_result:: a hash conforming to the output of
    #                 the TextSearcher::search method.
    def search_2_adoc(search_result)
      str = ""
      search_result.each do |filepath, info|
        str << ".From: '#{info[:doc_title]}'\n"
        str << "====\n\n"
        info[:sections].each do |section|
          str << "#{section[:url]}[#{section[:title]}]::\n\n"
          section[:lines].each do |line|
            str << line
          end.join("\n+\n")
          str << "\n\n"
        end
        str << "\n"
        str << "====\n"
      end

      <<~ADOC
        = Search Result

        #{str}
      ADOC
    end
  end

  class CGIRequestManager
    REQUIRED_PARAMS = %w[calling-url search-assets-top-rel search-phrase]
    OPTIONAL_PARAMS = %w[css-path consider-case as-regexp]

    class << self
      def searcher
        @searcher ||= TextSearcher.new(SearchRepoCache.new)
      end
    end

    def initialize(cgi, uri_mappings = nil, html_generator = nil)
      validate_request(cgi)

      @cgi = cgi
      @uri_mappings = uri_mappings || {"/" => "/var/www/html/"}
      @html_generator = html_generator || DefaultHtmlGenerator.new
    end

    def response
      sp = SearchParameters.from_hash(@cgi, uri_mappings: @uri_mappings)
      @html_generator.response(searcher.search(sp), sp.css_path)
    end

    private

    def searcher
      CGIRequestManager.searcher
    end

    def validate_request(cgi)
      REQUIRED_PARAMS.each { |p| raise ArgumentError, "Missing parameter: #{p}" unless cgi.key?(p) }
    end

    # put together a complete uri from the cgi parameters relevant to a search
    def assemble_uri(cgi)
      uri = cgi["calling-url"] + "?" + REQUIRED_PARAMS.collect { |p| "#{p}=#{cgi[p]}" }.join("&")
      uri + OPTIONAL_PARAMS.collect { |p| "#{p}=#{cgi[p]}" if cgi.key?(p) }.join("&")
    end

    def encode_query(cgi)
      query = URI.encode_www_form(
        REQUIRED_PARAMS.collect { |p| [p, cgi[p]] }.concat(
          OPTIONAL_PARAMS.collect { |p| [p, cgi[p]] if cgi.key?(p) }
        )
      )
      uri.query = query
    end
  end
end
