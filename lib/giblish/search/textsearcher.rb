require "pathname"
require "json"
require "uri"
require_relative "searchquery"
require_relative "../pathtree"

module Giblish
  # reads all lines in the given file at instantiation and
  # washes the text from some adoc formatting sequences.
  class LoadAdocSrcFromFile
    attr_reader :src_lines

    def initialize(filepath)
      @src_lines = []
      File.readlines(filepath.to_s, chomp: true, encoding: "UTF-8").each do |line|
        @src_lines << wash_line(line)
      end
    end

    private

    def wash_line(line)
      # remove some asciidoctor format sequences
      # '::', '^|===', '^==', '^--, ':myvar: ...'
      r = Regexp.new(/(::+|^[=|]+|^--+|^:\w+:.*$)/)
      line.gsub(r, "")
    end
  end

  # Encapsulates raw data and information deducable from one
  # search query
  class SearchParameters
    # a hash with { param => value } of all query parameters from the URI.
    attr_reader :parameters
    attr_reader :uri

    def self.from_uri(uri_str, uri_mappings: {"/" => "/var/www/html/"})
      q = SearchQuery.new(uri: uri_str)
      SearchParameters.new(query: q, uri_mappings: uri_mappings)
    end

    def self.from_hash(h, uri_mappings: {"/" => "/var/www/html/"})
      q = SearchQuery.new(query_params: h)
      SearchParameters.new(query: q, uri_mappings: uri_mappings)
    end

    def uri_path
      URI(calling_url).path
    end

    def assets_uri_path
      @assets_uri_path ||= Pathname.new(uri_path).dirname.join(search_assets_top_rel).cleanpath
      @assets_uri_path
    end

    # return:: the uri path pointing to the doc repo top dir
    def uri_path_repo_top
      Pathname.new(uri_path).join(search_assets_top_rel.dirname).dirname
    end

    # return:: the absolute Pathname of the file system path to the
    # search assets top dir.
    def assets_fs_path
      uri_to_fs(assets_uri_path)
    end

    def method_missing(meth, *args, &block)
      return @query.send(meth, *args, &block) if respond_to_missing?(meth)

      super(meth, args, &block)
    end

    def respond_to_missing?(meth, include_private = false)
      @query.respond_to?(meth)
    end

    # return:: the relative path from the doc top dir to the file
    def repo_file_path
      Pathname.new(uri_path).relative_path_from(uri_path_repo_top)
    end

    # repo_filepath:: the filepath from the repo top to a given file
    # fragment:: the fragment id or nil
    #
    # return:: the access url for a given section in a given src file
    def url(repo_filepath, fragment = nil)
      p = Pathname.new(repo_filepath)

      # create result by replacing relevant parts of the original uri
      res = URI(@query.calling_url)
      res.query = nil
      res.fragment = fragment
      res.path = uri_path_repo_top.join(p.sub_ext(".html")).cleanpath.to_s
      res
    end

    private

    # Search input:
    #
    # query:: a SearchQuery instance
    # uri_mappings:: mappings between uri.path prefix and an absolute path in the local
    #             file system. Ex {"/my/doc" => "/var/www/html/doc/repos"}. The default
    #             is { "/" => "/var/www/html" }
    #
    # ex URI = www.example.com/search/action?calling-uri=www.example.com/my/doc/repo/subdir/file1.html&search-assets-top-rel=../my/docs&search-phrase=hejsan
    def initialize(query:, uri_mappings: {"/" => "/var/www/html/"})
      @query = query

      # convert keys and values to Pathnames
      @uri_mappings = uri_mappings.map { |k, v| [Pathname.new(k).cleanpath, Pathname.new(v).cleanpath] }.to_h
      validate_parameters
    end

    # return:: a Pathname where the prefix of an uri path has been replaced with the
    #          corresponding fs mapping, if one exists. Returns the original pathname
    #          if no corresponding mapping exists.
    #          if more than one mapping match, the longest is used.
    def uri_to_fs(uri_path)
      up = Pathname.new(uri_path).cleanpath
      matches = {}

      @uri_mappings.each do |key, value|
        key_length = key.to_s.length
        # we must treat '/' specially since its the only case where
        # the key ends with a '/'
        s = key.root? ? "" : key
        tmp = up.sub(s.to_s, value.to_s).cleanpath
        matches[key_length] = tmp if tmp != up
      end
      return up if matches.empty?

      # return longest matching key
      matches.max { |item| item[0] }[1]
    end

    # Require that:
    #
    # - a relative asset path is included
    # - a search phrase is included
    # - the uri_mappings map an absolute uri path to an absolute, and existing file
    #   system path.
    def validate_parameters
      # asset_top_rel
      raise ArgumentError, "Asset top must be relative, found '#{search_assets_top_rel}'" if search_assets_top_rel.absolute?

      # uri_mapping
      @uri_mappings.each do |k, v|
        raise ArgumentError, "The uri path in the uri_mapping must be absolute, found: '#{k}'" unless k.absolute?
        raise ArgumentError, "The file system directory path must be absolute, found: '#{v}'" unless v.absolute?
        raise ArgumentError, "The file system diretory does not exist, found: '#{v}'" unless v.exist?
        raise ArgumentError, "The uri_mapping must be a directory, found file: '#{v}'" unless v.directory?
      end
    end
  end

  # Provides access to all search related info for one tree
  # of adoc src docs.
  class SearchDataRepo
    attr_reader :search_db, :src_tree, :db_mod_time

    SEARCH_DB_BASENAME = "heading_db.json"

    # assets_uri_path:: a Pathname to the top dir of the search asset folder
    def initialize(assets_fs_path)
      @assets_fs_path = assets_fs_path
      @search_db = read_search_db
      @src_tree = build_src_tree
    end

    # find section with closest lower line_no to line_info
    # NOTE: line_no in is 1-based
    def in_section(filepath, line_no)
      i = info(filepath)
      i[:sections].reverse.find { |section| line_no >= section[:line_no] }
    end

    # return:: the info from the repo for the given filepath or nil if no info
    #          exists
    def info(filepath)
      @search_db[:fileinfos].find { |info| info[:filepath] == filepath.to_s }
    end

    def is_stale
      @db_mod_time != File.stat(db_filepath.to_s).mtime
    end

    private

    def build_src_tree
      # setup the tree of source files and pro-actively read in all text
      # into memory
      src_tree = PathTree.build_from_fs(@assets_fs_path, prune: false) do |p|
        p.extname.downcase == ".adoc"
      end
      src_tree.traverse_preorder do |level, node|
        next unless node.leaf?

        node.data = LoadAdocSrcFromFile.new(node.pathname)
      end
      src_tree
    end

    def db_filepath
      @assets_fs_path.join(SEARCH_DB_BASENAME)
    end

    def read_search_db
      # read the heading_db from file
      @db_mod_time = File.stat(db_filepath.to_s).mtime
      json = File.read(db_filepath.to_s)
      JSON.parse(json, symbolize_names: true)
    end
  end

  # Caches a number of SearchDataRepo instances in memory and returns the
  # one corresponding to the given SearchParameters instance.
  class SearchRepoCache
    def initialize
      @repos = {}
    end

    # search_parameters:: a SearchParameters instance
    #
    # returns:: the SearchDataRepo corresponding to the given search parameters
    def repo(search_parameters)
      ap = search_parameters.assets_fs_path

      # check if we shall read a new repo from disk
      if !@repos.key?(ap) || @repos[ap].is_stale
        # puts "read from disk for ap: #{ap}.."
        # puts "is stale" if @repos.key?(ap) && @repos[ap].is_stale
        @repos[ap] = SearchDataRepo.new(ap)
      end

      @repos[ap]
    end
  end

  # Provides text search capability for the given source repository.
  class TextSearcher
    def initialize(repo_cache)
      @repo_cache = repo_cache
    end

    # transform the output from grep_tree to an Array of hashes according to:
    #
    # {Pathname("subdir/file1.adoc") => {
    #   doc_title: "My doc!!",
    #   sections: [{
    #     url: URI("http://my.site.com/docs/repo1/file1.html#section_id_1"),
    #     title: "Purpose",
    #     lines: [
    #       "this is the line with matching text",
    #       "this is another line with matching text"
    #     ]
    #   }]
    # }}
    # search_params:: a SearchParameters instance
    def search(search_params)
      repo = @repo_cache.repo(search_params)

      grep_results = grep_tree(repo, search_params)

      search_result(repo, grep_results, search_params)
    end

    # result = {
    #   filepath => [{
    #     line_no: nil,
    #     line: ""
    #   }]
    # }
    def grep_tree(repo, search_params)
      result = Hash.new { |h, k| h[k] = [] }

      # handle case-sensitivity and input as regex pattern or string
      r_flags = search_params.consider_case? ? 0 : Regexp::IGNORECASE
      r_str = search_params.as_regexp? ? search_params.search_phrase : Regexp.escape(search_params.search_phrase)
      r = Regexp.new(r_str, r_flags)

      # find all matching lines in the src tree
      repo.src_tree.traverse_preorder do |level, node|
        next unless node.leaf?

        relative_path = node.relative_path_from(repo.src_tree)
        line_no = 0
        node.data.src_lines.each do |line|
          line_no += 1
          next if line.empty? || !r.match?(line)

          # replace match with an embedded rule that can
          # be styled
          result[relative_path] << {
            line_no: line_no,
            line: line.gsub(r, '[.red]##*_\0_*##')
          }
        end
      end
      result
    end

    # returns:: a hash described in the 'search' method doc
    def search_result(repo, grep_result, search_params)
      result = Hash.new { |h, k| h[k] = [] }

      grep_result.each do |filepath, matches|
        db = repo.info(filepath)
        next if db.nil?

        sect_to_match = Hash.new { |h, k| h[k] = [] }
        matches.each do |match|
          s = repo.in_section(filepath, match[:line_no])
          sect_to_match[s] << match
        end

        sections = sect_to_match.collect do |section, matches|
          {
            url: search_params.url(filepath, section[:id]),
            title: section[:title],
            lines: matches.collect { |match| match[:line].chomp }
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
