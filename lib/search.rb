#!/usr/bin/env ruby

require "pathname"
require "json"
require "asciidoctor"
require "open3"
require "cgi"

class GrepDocTree
  Line_info = Struct.new(:line, :line_no) {
    def initialize(line,line_no)
      self.line = line
      self.line_no = Integer(line_no)
    end
  }

  # grep_opts:
  # :search_top
  # :search_phrase
  # :ignorecase
  # :useregexp
  def initialize(grep_opts)
    @grep_opts = "-nHr --include '*.adoc' "
    @grep_opts += "-i " if grep_opts.has_key? :ignorecase
    @grep_opts += "-F " unless grep_opts.has_key? :useregexp

    @search_root = grep_opts[:search_top]
    @input = grep_opts[:search_phrase]

    @output = ""
    @error = ""
    @status = 0
    @match_index = {}
  end

  def grep
    # This console code sequence will only show the matching word in bold ms=01:mc=:sl=:cx=:fn=:ln=:bn=:se=
    grep_env="GREP_COLORS=\"ms=01:mc=:sl=:cx=:fn=:ln=:bn=:se=\""
    @grep_opts += " --color=always"


    @output, @error, @status = Open3.capture3("#{grep_env} grep #{@grep_opts} \"#{@input}\" #{@search_root}")

    begin
      @output.force_encoding(Encoding::UTF_8)
      @output.gsub!(/\x1b\[01m\x1b\[K/,"##")
      @output.gsub!(/\x1b\[m\x1b\[K/,"##")
    rescue StandardError => e
      print e.message
      print e.backtrace.inspect
      exit 0
    end

    grep2hash @search_root
  end

  # returns an indexed output where each match from the search is associated with the
  # corresponding src file's closest heading.
  # the format of the output:
  # {html_filename#heading : [line_1, line_2, ...], ...}
  #
  # The heading_db has the following JSON format
  # {
  #   file_infos : [{
  #     filepath : filepath_1,
  #     title : Title,
  #     sections : [{
  #       id : section_id_1,
  #       title : section_title_1,
  #       line_no : line_no
  #     },
  #     {
  #       id : section_id_1,
  #       title : section_title_1,
  #       line_no : line_no
  #     },
  #     ...
  #     ]
  #   },
  #   {
  #     filepath : filepath_1,
  #     ...
  #   }]
  # }
  def match_with_headings heading_db
    matches = []

    # for each file with at least one match
    @match_index.each do |file_path,match_infos|
      # assume that max one file with the specified path
      # exists
      files = heading_db["file_infos"].select do |fi|
        fi["filepath"] == file_path.to_s
      end
      next if files.empty?

      file_anchors = construct_user_info files.first, match_infos
      matches << file_anchors
      end
    matches
  end

  # Produce a hash with all info needed for the user to navigate to the
  # matching html section for all matches to the file in the supplied file
  # info hash.
  #
  # format of the resulting hash:
  # {
  #   filepath : Filepath,
  #   title : Title,
  #   matches : {
  #       section_id :
  #       {
  #         section_title : Section Title,
  #         location : Location,
  #         lines : [line_1, line_2, ...]
  #       }
  #     }
  #   ]
  # }
  #
  def construct_user_info file_info, match_infos
    matches = {}
    file_anchors = {
        "filepath" => file_info["filepath"],
        "title" => file_info["title"],
        "matches" => matches
    }

    match_infos.each do |match_info|
      match_line_nr = match_info.line_no

      # find section with closest lower line_no to line_info
      best_so_far = 1
      chosen_section_info = {}
      file_info["sections"].each do |section_info|
        l = Integer(section_info["line_no"])
        if l <= match_line_nr && l > best_so_far
          chosen_section_info = section_info
        end
      end

      matches[chosen_section_info["id"]] =
          {
              "section_title" => chosen_section_info["title"],
              "location" => "#{Pathname.new(file_info["filepath"]).sub_ext(".html").to_s}##{chosen_section_info["id"]}",
              "lines" => []
          } unless matches.key?(chosen_section_info["id"])
      matches[chosen_section_info["id"]]["lines"] << match_info.line
    end
    file_anchors
  end

  def formatted_output
    # assume we have an updated index
    adoc_str = ""
    @match_index.each do |k,v|
      adoc_str += "#{k}::\n"
      v.each { |line_info|
        adoc_str += "#{line_info.line_no} : #{line_info.line}\n"
      }
    end
    adoc_str
  end

  private

  # converts the 'raw' matches from grep into a hash.
  # i.e. from:
  # <filename>:<line_no>:<line>
  # <filename>:<line_no>:<line>
  # ...
  #
  # to
  # {file_path : [line_info1, line_info2, ...], ...}
  def grep2hash(base_dir)
    @match_index = {}
    @output.split("\n").each do |line|
      tokens = line.split(":",3)

      # remove all lines starting with :<attrib>:
      tokens[2].gsub!(/^:[[:graph:]]+:.*$/,"")
      next if tokens[2].empty?

      # remove everything above the repo root from the filepath
      file_path = Pathname.new(tokens[0]).relative_path_from Pathname.new(base_dir)
      @match_index[file_path] = [] unless @match_index.key? file_path
      @match_index[file_path] << Line_info.new(tokens[2], tokens[1])
    end
  end
end

class SearchDocTree
  def initialize(input_data)
    @input_data = input_data
  end

  def search
    # read the heading_db from file
    jsonpath = @input_data[:search_top].join("heading_index.json")
    src_index = {}
    json = File.read(jsonpath.to_s)
    src_index = JSON.parse(json)

    # search the doc tree for regex
    gt = GrepDocTree.new @input_data
    gt.grep

    matches = gt.match_with_headings src_index
    format_search_adoc matches
  end

  private

  def wash_line line
    # remove any '::'
    result = line.gsub(/::*/,"")
    # remove =,| at the start of a line
    result.gsub!(/^[=|]+/,"")
    result
  end

  # index is an array of file_info, see construct_user_info
  # for format per file
  # == Title (filename)
  #
  # <<location,section_title>>::
  # line_1
  # line_2
  # ...
  def format_search_adoc index
    str = ""
    index.each do |file_info|
      filename = Pathname.new(file_info["filepath"]).basename
      str << "== #{file_info["title"]}\n\n"
      file_info["matches"].each do |section_id, info |
        str << "<<#{info["location"]},#{info["section_title"]}>>::\n\n"
        str << "[subs=\"quotes\"]\n"
        str << "----\n"
        info["lines"].each do | line |
          str << "-- #{wash_line(line)}\n"
        end.join("\n\n")
        str << "----\n"
      end
      str << "\n"
    end

    <<~ADOC
    = Search Result

    #{str}
    ADOC
  end
end

def init_web_server web_root
  require 'webrick'

  root = File.expand_path web_root
  puts "Trying to start a WEBrick instance at port 8000 serving files from #{web_root}..."
  server = WEBrick::HTTPServer.new :Port => 8000, :DocumentRoot => root
  puts "WEBrick instance now listening to localhost:8000"

  trap 'INT' do server.shutdown end

  server.start
end

def cgi_main
  # init a new cgi 'connection'
  cgi = CGI.new

  # retrieve the form data supplied by user
  input_data = {
      search_phrase: cgi["searchphrase"],
      ignorecase: cgi.has_key?("ignorecase"),
      useregexp: cgi.has_key?("useregexp"),
      index_dir: Pathname.new(cgi["topdir"]),
      client_css: cgi["css"],
      search_top: nil,
      styles_top: nil
  }

  # fixup paths depending on git branch or not
  #
  # if the source was rendered from a git branch, the paths
  # search_assets = <index_dir>/../search_assets/<branch_name>/
  # styles_dir = ../web_assets/css
  #
  # and if not, the path is
  # search_assets = <index_dir>/search_assets
  # styles_dir = ./web_assets/css
  if input_data[:index_dir].join("./search_assets").exist?
    input_data[:search_top] = input_data[:index_dir].join("./search_assets")
    input_data[:styles_top] = Pathname.new("./web_assets/css")
  elsif input_data[:index_dir].join("../search_assets").exist?
    input_data[:search_top] = input_data[:index_dir].join("../search_assets").join(index_dir.basename)
    input_data[:styles_top] = Pathname.new("../web_assets/css")
  else
    raise ScriptError, "Could not find search_assets dir!"
  end

  # use a relative stylesheet (same as the index page was rendered with)
  adoc_options =  {
      "data-uri" => 1,
      "linkcss" => 1,
      "stylesdir" => input_data[:styles_top].to_s,
      "stylesheet" => input_data[:client_css],
      "copycss!" => 1
  }

  # search the docs and render html
  sdt = SearchDocTree.new(input_data)
  docstr = sdt.search

  # send the result back to the client
  print cgi.header
  print Asciidoctor.convert docstr, header_footer: true, attributes: adoc_options
end

# assume that the file tree looks like this when running
# on a git branch:
#
# dst_root_dir
# |- web_assets
# |- branch_1_top_dir
# |     |- index.html
# |     |- file_1.html
# |     |- dir_1
# |     |   |- file2.html
# |- branch_2_top_dir
# |- branch_x_...
# |- search_assets
# |     |- branch_1_top_dir
# |           |- heading_index.json
# |           |- file1.adoc
# |           |- dir_1
# |           |   |- file2.html
# |           |- ...
# |     |- branch_2_top_dir
# |           | ...

# assume that the file tree looks like this when not
# rendering a git branch:
#
# dst_root_dir
# |- index.html
# |- file_1.html
# |- dir_1
# |   |- file2.html
# |...
# |- web_assets (only if a custom stylesheet is used...)
# |- search_assets
# |     |- heading_index.json
# |     |- file1.adoc
# |     |- dir_1
# |     |   |- file2.html
# |     |- ...



# Usage:
#   to start a local web server for development work
# giblish-search.rb <web_root>
#
#   to run as a cgi script via a previously setup web server:
# giblish-search.rb
#
if __FILE__ == $PROGRAM_NAME

  if ARGV.length == 0
    # 'Normal' cgi usage, as called from a web server
    cgi_main
    exit 0
  end

  if ARGV.length == 1
    # Run a simple web server to test this locally..
    # and then create the html docs using:
    # giblish -c -m -w <web_root> -r <resource_dir> -s <style_name> -g <git_branch> <src_root> <web_root>
    init_web_server ARGV[0]
    exit 0
  end
end
