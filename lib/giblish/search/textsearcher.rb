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
      File.readlines(filepath.to_s) do |line|
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
    # uri_mappings:: mappings between uri.path prefix and an absolute path in the local
    #             file system. Ex {"/my/doc" => "/var/www/html/doc/repos"}. The default
    #             is { "/" => "/var/www/html" }
    #
    # ex URI = www.example.com/my/doc/repo/subdir/file1.html?search-assets-top-rel=../my/docs&searchphrase=hejsan
    def initialize(calling_uri:, uri_mappings: {"/" => "/var/www/html"})
      @uri = URI(calling_uri)

      # convert keys and values to Pathnames
      @uri_mappings = uri_mappings.map { |k, v| [Pathname.new(k).cleanpath, Pathname.new(v).cleanpath] }.to_h

      @parameters = URI.decode_www_form(@uri.query).to_h

      validate_parameters
    end

    # return::
    def assets_uri_path
      @assets_uri_path ||= Pathname.new(@uri.path).dirname.join(assets_top_rel).cleanpath
      @assets_uri_path
    end

    # return:: the uri path pointing to the doc repo top dir
    def uri_path_repo_top
      Pathname.new(@uri.path).join(assets_top_rel.dirname).dirname
    end

    # return:: the absolute Pathname of the file system path to the
    # search assets top dir.
    def assets_fs_path
      uri_to_fs(assets_uri_path)
    end

    # return:: a Pathname with the relative dir from the file in the
    # given url to the asset top
    def assets_top_rel
      Pathname.new(parameters["search-assets-top-rel"])
    end

    # return:: the relative path from the doc top dir to the file
    def repo_file_path
      Pathname.new(uri.path).relative_path_from(uri_path_repo_top)
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
      raise ArgumentError, "Missing relative asset path!" if assets_top_rel.nil?
      raise ArgumentError, "Asset top must be relative, found '#{assets_top_rel}'" if assets_top_rel.absolute?

      # search phrase
      raise ArgumentError, "No search phrase found!" if searchphrase.nil?

      # uri_mapping
      @uri_mappings.each do |k, v|
        raise ArgumentError, "The uri path in the uri_mapping must be absolute, found: '#{k}'" unless k.absolute?
        raise ArgumentError, "The file system directory path must be absolute, found: '#{v}'" unless v.absolute?
        raise ArgumentError, "The file system diretory does not exist, found: '#{v}'" unless v.exist?
        raise ArgumentError, "The uri_mapping must be a directory, found file: '#{v}'" unless v.directory?
      end
    end
  end

  class SearchRepoCache
    def initialize
      @repos = {
        assets_uri_path: "", data: {
          repo: SearchDataRepo.new,
          db_mod_time: time
        }
      }
    end

    def repo(assets_uri_path)
      @repos[ap] ||= {assets_uri_path: assets_uri_path, data: {repo: SearchDataRepo.new, db_mod_time: nil}}
      # TODO: Add time mod check here for reload of repo
    end
  end

  # Provides access to all search related info for one tree
  # of adoc src docs.
  class SearchDataRepo
    attr_reader :search_db

    SEARCH_DB_BASENAME = "heading_db.json"

    # assets_uri_path:: a Pathname to the top dir of the search asset folder
    def initialize(assets_uri_path)
      @assets_uri_path = assets_uri_path
      @search_db = cache_search_db
      @db_fileinfos = @search_db[:fileinfos]
      @src_tree = cache_src_tree
    end

    # find section with closest lower line_no to line_info
    # NOTE: line_no in is 1-based
    def in_section(filepath, line_no)
      i = info(filepath)
      i[:sections].reverse.find { |section| line_no >= section[:line_no] }
    end

    private

    # return:: the info from the repo for the given filepath or nil if no info
    #          exists
    def info(filepath)
      @search_db[:fileinfos].find { |info| info[:filepath] == filepath }
    end

    def cache_src_tree
      # setup the tree of source files and pro-actively read in all text
      # into memory
      # TODO: Add a mechanism that triggers re-read when the file time-stamp
      # has changed
      src_tree = PathTree.build_from_fs(@assets_uri_path, prune: false) do |p|
        p.extname.downcase == ".adoc"
      end
      src_tree.traverse_preorder do |level, node|
        next unless node.leaf?

        node.data = LoadAdocSrcFromFile.new(node.pathname)
      end
    end

    def cache_search_db
      # read the heading_db from file
      json = File.read(@assets_uri_path.join(SEARCH_DB_BASENAME).to_s)
      @search_db = JSON.parse(json, symbolize_names: true)
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

          relative_path = node.relative_path_from(@data_repo.assets_uri_path)
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
