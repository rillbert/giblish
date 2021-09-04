require "pathname"
require "json"

module Giblish
  SEARCH_DB_BASENAME = "heading_db.json"
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

  # Provides access to all search related info for one tree
  # of adoc src docs.
  SearchDataRepo = Struct.new(:url_top, :uri_path, :search_asset_topdir) do
    def src_tree
      return src_tree unless src_tree.nil?

      # setup the tree of source files and pro-actively read in all text
      # into memory
      # TODO: Add a mechanism that triggers re-read when the file time-stamp
      # has changed
      src_tree = PathTree.build_from_fs(asset_path, prune: true) do |p|
        p.extname.downcase == ".adoc"
      end
      src_tree.traverse_preorder do |level, node|
        node.data = LoadAdocSrcFromFile.new(node.pathname)
      end
    end

    def asset_path
      return asset_path unless asset_path.nil?

      self.asset_path = (Pathname.new(uri_path) / search_asset_topdir).cleanpath
    end

    def search_db
      return search_db unless search_db.nil?

      # read the heading_db from file
      json = File.read((search_asset_topdir / join(SEARCH_DB_BASENAME)).to_s)
      self.search_db = JSON.parse(json)
    end

    def url(filepath, section)
    end

    # find section with closest lower line_no to line_info
    def in_section(filepath, match_data)
      sections = search_db[filepath]
      sections.reverse.find { |section| match_data[:line_no] >= Integer(section[:line_no]) }
    end
  end

  # Provides text search capability for the given source repository.
  class TextSearcher
    def initialize(search_data_repo)
      @data_repo = search_data_repo
    end

    def search(search_phrase, opts)
      # TODO: Handle search options!
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
