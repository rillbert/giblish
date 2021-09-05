require "pathname"
require "json"
require "uri"

module Giblish
  # reads all lines in the given file at instantiation and
  # washes the text from some adoc formatting sequences.
  class LoadAdocSrcFromFile
    attr_reader :src_lines

    def initialize(filepath)
      @src_lines = []
      File.readlines do |line|
        @src_lines << wash_line(line)
      end
    end

    def wash_line(line)
      # remove some asciidoctor format sequences
      # '::', '^|===', '^==', '^--, ':myvar: ...'
      r = Regexp.new(/(::+|^[=|]+|^--+|^:\w:.*$)/)
      line.gsub(r, "")
    end
  end

  class SearchParameters
    # a hash with { param => value } of all query parameters from the URI.
    attr_reader :parameters
    attr_reader :uri

    # Search input:
    #
    # calling_uri:: the full URI of the originating search request
    #
    # ex URI = www.example.com/my/doc/repo/subdir/file1.html?search-assets-top-rel=../my/docs&searchphrase=hejsan
    def initialize(calling_uri:)
      @uri = URI(calling_uri)
      @parameters = URI.decode_www_form(@uri.query).to_h

      validate_parameters
    end

    def assets_uri_path
      @assets_uri_path ||= Pathname.new(@uri.path).dirname.join(assets_top_rel).cleanpath
      @assets_uri_path
    end

    # returns:: a Pathname with the relative dir to asset top
    def assets_top_rel
      Pathname.new(parameters["search-assets-top-rel"])
    end

    def searchphrase
      parameters["searchphrase"]
    end

    def css_path
      parameters["css-path"]
    end

    def consider_case?
      parameters.key?("consider-case")
    end

    def as_regexp?
      parameters.key?("as-regexp")
    end

    private

    # Require that:
    #
    # - a relative asset path is included
    # - a search phrase is included
    def validate_parameters
      # asset_top_rel
      raise ArgumentError, "Missing relative asset path!" if assets_top_rel.nil?
      raise ArgumentError, "Asset top must be relative, found '#{assets_top_rel}'" if assets_top_rel.absolute?

      # search phrase
      raise ArgumentError, "No search phrase found!" if searchphrase.nil?
    end
  end

  class SearchRepoCache
    def initialize
      @repos = {
        asset_path: "", data: {
          repo: SearchDataRepo.new,
          db_mod_time: time
        }
      }
    end

    def repo(asset_path)
      @repos[ap] ||= {asset_path: asset_path, data: {repo: SearchDataRepo.new, db_mod_time: nil}}
      # TODO: Add time mod check here for reload of repo
    end
  end

  # Provides access to all search related info for one tree
  # of adoc src docs.
  class SearchDataRepo
    SEARCH_DB_BASENAME = "heading_db.json"

    # asset_path:: a Pathname to the top dir of the search asset folder
    def initialize(asset_path)
      @asset_path = asset_path
      @search_db = cache_search_db
      @src_tree = cache_src_tree
    end

    # find section with closest lower line_no to line_info
    def in_section(filepath, match_data)
      sections = search_db[filepath]
      sections.reverse.find { |section| match_data[:line_no] >= Integer(section[:line_no]) }
    end

    private

    def cache_src_tree
      # setup the tree of source files and pro-actively read in all text
      # into memory
      # TODO: Add a mechanism that triggers re-read when the file time-stamp
      # has changed
      src_tree = PathTree.build_from_fs(@asset_path, prune: true) do |p|
        p.extname.downcase == ".adoc"
      end
      src_tree.traverse_preorder do |level, node|
        node.data = LoadAdocSrcFromFile.new(node.pathname)
      end
    end

    def cache_search_db
      # read the heading_db from file
      json = File.read((@asset_path / join(SEARCH_DB_BASENAME)).to_s)
      self.search_db = JSON.parse(json)
    end
  end

  # Provides text search capability for the given source repository.
  class TextSearcher
    def initialize(repo_cache)
      @repo_cache = repo_cache
    end

    def search(search_parameters)
      search_result(grep_tree(search_phrase))
    end

    # result = {
    #   filepath => [{
    #     line_no: nil,
    #     line: ""
    #   }]
    # }
    def grep_tree(search_phrase)
      # TODO: Add ignore case and use regex options
      result = Hash.new { |h, k| h[k] = [] }
      r = Regexp.new(search_phrase)

      # find all matching lines in the src tree
      data_repo.src_tree.traverse_preorder do |level, node|
        line_no = 0
        node.data.src_lines do |line|
          line_no += 1
          next if line.empty? || !r.match?(line)

          relative_path = node.relative_path_from(@data_repo.asset_path)
          result[relative_path] << {
            line_no: line_no,
            # replace match with an embedded rule that can
            # be styled
            line: line.gsub(r, '[.match]#\0#')
          }
        end
      end
      result
    end

    # transform the output from grep_tree to an Array of hashes according to:
    # {"subdir/file1.adoc" => {
    #   doc_title: "My doc!!",
    #   sections: [{
    #     url: "http://my.site.com/docs/repo1/file1.html#section_id_1",
    #     title: "Purpose",
    #     lines: [
    #       "this is the line with matching text",
    #       "this is another line with matching text"
    #     ]
    #   }]
    # }}
    def search_result(grep_result)
      db = @data_repo.search_db
      result = Hash.new { |h, k| h[k] = [] }

      grep_result.each do |filepath, matches|
        db = @data_repo.search_db[filepath]
        next if db.nil?

        sect_to_match = Hash.new { |h, k| h[k] = [] }
        matches.each do |match|
          s = @data_repo.in_section(filepath, match)
          sect_to_match[s] << match
        end

        sections = s.collect do |section, matches|
          {
            url: @data_repo.url(filepath, section),
            title: section[:title],
            lines: matches.collect { |match| m.line }
          }
        end

        result[filepath] = {
          doc_title: db[:title],
          sections: sections
        }
      end
      result
    end
  end
end
