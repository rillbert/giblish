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

  def initialize(top_dir, input_str, is_case_sensitive = true)
    @grep_opts = "-nHr"
    @grep_opts += "i" unless is_case_sensitive
    @grep_opts += " --include '*.adoc'"
    @top_dir = Pathname.new top_dir
    @input = input_str
    @output = ""
    @error = ""
    @status = 0
    @match_index = {}
  end

  def grep
    # This console code sequence will only show the matching word in bold ms=01:mc=:sl=:cx=:fn=:ln=:bn=:se=
    grep_env="GREP_COLORS=\"ms=01:mc=:sl=:cx=:fn=:ln=:bn=:se=\""
    @grep_opts += " --color=always"


    @output, @error, @status = Open3.capture3("#{grep_env} grep #{@grep_opts} \"#{@input}\" #{@top_dir}")

    begin
      @output.force_encoding(Encoding::UTF_8)
      @output.gsub!(/\x1b\[01m\x1b\[K/,"##")
      @output.gsub!(/\x1b\[m\x1b\[K/,"##")
    rescue StandardError => e
      print e.message
      print e.backtrace.inspect
      exit 0
    end

    reindex_result @top_dir
  end

  # returns an indexed output where each match from the search is associated with the
  # corresponding src file's closest heading.
  # the format of the output:
  # {html_filename#heading : [line_1, line_2, ...], ...}
  #
  # The src info index has the following JSON format
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
  def index_output src_index
    matches = []
    # for each file with at least one match
    @match_index.each do |file_path,match_infos|
      # assume that max one file with the specified path
      # exists
      files = src_index["file_infos"].select do |fi|
        fi["filepath"] == file_path.to_s
      end
      next if files.empty?

      file_anchors = index_one_file files.first,match_infos
      matches << file_anchors
      end
    matches
  end

  # format:
  #
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
  def index_one_file file_info, match_infos
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
              "location" => "#{Pathname.new(@top_dir.basename).join(file_info["filepath"]).sub_ext(".html").to_s}##{chosen_section_info["id"]}",
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

  # indexes the 'raw' matches from grep into a hash
  # with format
  # {file_path : [line_info1, line_info2, ...], ...}
  def reindex_result(base_dir)
    # grep format is
    # <filename>:<line_no>:<line>
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

# index is an array of file_info, see index_one_file
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

# top_dir = Pathname where the heading_index.json is located
def perform_search(top_dir, search_phrase)
  top_dir = Pathname.new(top_dir) unless top_dir.respond_to?(:join)

  # read the src_index from file
  jsonpath = top_dir.join("heading_index.json")
  src_index = {}
  json = File.read(jsonpath.to_s)
  src_index = JSON.parse(json)

  # search the doc tree for regex
  gt = GrepDocTree.new "#{top_dir}",search_phrase,true
  gt.grep

  matches = gt.index_output src_index
  format_search_adoc matches

end

def cgi_search
  cgi = CGI.new

  # get top dir for search_assets
  index_dir = Pathname.new(cgi["topdir"])
  top_dir = index_dir.join("../search_assets").join(index_dir.basename)

  print cgi.header
  docstr = perform_search top_dir, cgi["searchphrase"]
  print Asciidoctor.convert docstr, header_footer: true
end

def cmd_search(top_dir, search_phrase)
  docstr = perform_search top_dir, search_phrase
  print Asciidoctor.convert docstr, header_footer: true
  # puts docstr
end

# assume that the file tree looks like when running
# on a git branch
#
# top_dir
# |- web_assets
# |- branch_1_top_dir
# |     |- index.html
# |     |- file_1.html
# |     |- dir_1
# |     |   |- file2.html
# |- search_assets
# |     |- branch_1
# |           |- heading_index.json
# |           |- file1.adoc
# |           |- dir_1
# |           |   |- file2.html
# |           |- ...
# |     |- branch_2
# |           | ...
# |- branch_2_top_dir
# | ...
#
# test the class...
if __FILE__ == $PROGRAM_NAME

#  init_web_server
#  exit 0

  # provide_hello_world
  # exit 0

  cgi_search
  exit 0

  # cmd_search(
  #     "/home/anders/repos/gendocs/search_assets/personal_rillbert_SWD-54_refactor_swd_doc",
  #     "Vironova"
  # )
  # exit 0


#   base_dir = "/home/anders/vironova/repos/qms"
#   gt = nil
#
#   # read the src_index from file
#   jsonpath = Pathname.new("/home/anders/repos/gendocs/heading_index.json").to_s
#   src_index = {}
#   json = File.read(jsonpath)
#   src_index = JSON.parse(json)
#
#   # search the doc tree for regex
#   time = Benchmark.measure {
#     gt = GrepDocTree.new "#{base_dir}/qms","Sentinel",true
#     gt.grep base_dir
#   }
#
#
#   matches = gt.index_output src_index
#   docstr = format_search_adoc matches
#   puts docstr
#
# #  File.open("search_result.html","w") do |f|
# #    f.write Asciidoctor.convert docstr, header_footer: true
# #  end
#   cgi = CGI.new
#   print cgi.header
#   print Asciidoctor.convert docstr, header_footer: true
#
#   # puts "Done."
  # puts time
end
