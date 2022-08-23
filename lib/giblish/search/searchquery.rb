module Giblish
  class SearchQuery
    attr_reader :parameters

    REQUIRED_PARAMS = %w[calling-url search-assets-top-rel search-phrase]
    OPTIONAL_PARAMS = %w[css-path consider-case as-regexp]

    def initialize(uri: nil, query_params: nil)
      @parameters = case [uri, query_params]
      in [String, nil]
        uri_2_params(uri)
      in [nil, _]
        validate_parameters(query_params)
      else
        raise ArgumentError, "You must supply one of 'uri: [String]' or 'query_params: [Hash]' got: #{query_params}"
      end
    end

    def css_path
      @parameters.key?("css-path") && !@parameters["css-path"].empty? ? Pathname.new(@parameters["css-path"]) : nil
    end

    def search_assets_top_rel
      # convert to pathname and make sure we always are relative
      Pathname.new("./" + @parameters["search-assets-top-rel"]).cleanpath
    end

    def consider_case?
      @parameters.key?("consider-case")
    end

    def as_regexp?
      @parameters.key?("as-regexp")
    end

    def method_missing(meth, *args, &block)
      unless respond_to_missing?(meth)
        super(meth, *args, &block)
        return
      end

      @parameters[meth.to_s.tr("_", "-")]
    end

    def respond_to_missing?(method_name, include_private = false)
      @parameters.key?(method_name.to_s.tr("_", "-"))
    end

    private

    def uri_2_params(uri_str)
      uri = URI(uri_str)
      raise ArgumentError, "No query parameters found!" if uri.query.nil?

      parameters = URI.decode_www_form(uri.query).to_h
      validate_parameters(parameters)
    end

    #  validate that all required parameters are included
    def validate_parameters(uri_params)
      REQUIRED_PARAMS.each do |p|
        raise ArgumentError, "Missing or empty parameter: #{p}" if !uri_params.key?(p) || uri_params[p].empty?
      end

      uri_params
    end
  end
end
