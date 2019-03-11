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

require 'benchmark'

def init_web_server
  require 'webrick'

  root = File.expand_path '~/repos/gendocs'
  server = WEBrick::HTTPServer.new :Port => 8000, :DocumentRoot => root

  trap 'INT' do server.shutdown end

  server.start
end

def provide_hello_world
  cgi = CGI.new

  docstr = <<~ADOC
    = A dynamically made doc
    :toc: left
    :numbered:
    
    == The query params
    
    I received the following paramters: #{cgi.keys}

    The user came here from: #{ENV["HTTP_REFERER"]}

    == useful data 

    Params: #{cgi.params.inspect}

    Env: #{ENV.inspect}

  ADOC

  print cgi.header
  print Asciidoctor.convert docstr, header_footer: true
end

# search_assets_top_dir = Pathname where the heading_index.json is located
def perform_search(input_data)

  # read the heading_db from file
  jsonpath = input_data[:search_top].join("heading_index.json")
  src_index = {}
  json = File.read(jsonpath.to_s)
  src_index = JSON.parse(json)

  # search the doc tree for regex
  gt = GrepDocTree.new input_data
  gt.grep

  matches = gt.match_with_headings src_index
  format_search_adoc matches

end

def cgi_search
  cgi = CGI.new


  # retrieve the form data supplied by user
  input_data = {
      search_phrase: cgi["searchphrase"],
      ignorecase: cgi.has_key?("ignorecase"),
      useregexp: cgi.has_key?("useregexp"),
      index_dir: Pathname.new(cgi["topdir"]),
      search_top: nil,
      styles_top: nil
  }

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

  # set a relative stylesheet
  adoc_options =  {
      "data-uri" => 1,
      "linkcss" => 1,
      "stylesdir" => input_data[:styles_top].to_s,
      # FIX This hard-coded value...
      "stylesheet" => "qms.css",
      "copycss!" => 1
  }

  # render the html via the asciidoctor engine
  print cgi.header
  docstr = perform_search input_data
  print Asciidoctor.convert docstr, header_footer: true, attributes: adoc_options
end

def cmd_search(top_dir, search_phrase)
  docstr = perform_search top_dir, search_phrase
  # set a relative stylesheet
  adoc_options =  {
      "linkcss" => 1,
      "stylesdir" => "#{Pathname.new(top_dir).join("../../web_assets/css")}",
      "stylesheet" => "qms.css",
      "copycss!" => 1
  }

  print Asciidoctor.convert docstr, header_footer: true, attributes: adoc_options
#  print Asciidoctor.convert docstr, header_footer: true
#  puts docstr
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


# test the class...
if __FILE__ == $PROGRAM_NAME

  ## To run a simple web server to test this locally, uncomment the following two lines:
  # init_web_server
  #  exit 0

  # and then create the html docs using:
  #  lib/giblish.rb -c -m -w /home/anders/repos/gendocs -r /home/anders/vironova/repos/qms/scripts/docgeneration/resources/ -s qms -g main ~/vironova/repos/qms/qms/ ../gendocs


  # provide_hello_world
  # exit 0

  cgi_search
  exit 0

  # cmd_search(
  #     "/home/anders/repos/gendocs/search_assets/personal_rillbert_SWD-54_refactor_swd_doc",
  #     "Vironova"
  # )
  # exit 0

end
