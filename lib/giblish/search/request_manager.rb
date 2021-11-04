require "asciidoctor"
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

  # A gateway class that implements everything needed to produce
  # an html page with search results given a search request.
  # 
  # The class implements internal caching for better performance. It
  # is thus probably wise to instantiate this class once and then use
  # that instance for all subsequent search queries.
  class RequestManager
    # url_path_mappings:: a Hash with mappings from url paths to
    # local file system directories.
    # html_generator:: an object that generates html by implementing
    # the method 'def response(search_result, css_path = nil)'. See
    # eg DefaultHtmlGenerator. If nil, a DefaultHtmlGenerator is used.
    def initialize(uri_mappings, html_generator = nil)
      @uri_mappings = uri_mappings || {"/" => "/var/www/html/"}

      @html_generator = html_generator || DefaultHtmlGenerator.new
    end

    # Return an html page with the search result from the given query.
    #
    # search_params:: a Hash containing the parameters of the search query.
    def response(search_params)
      sp = SearchParameters.from_hash(search_params, uri_mappings: @uri_mappings)
      @html_generator.response(searcher.search(sp), sp.css_path)
    end

    private 

    # a convenience method to give shorter access to the class-wide
    # TextSearcher instance.
    def searcher
      RequestManager.searcher
    end

    # provide a class-wide TextSearcher instance
    class << self
      def searcher
        @searcher ||= TextSearcher.new(SearchRepoCache.new)
      end
    end
  end
end
