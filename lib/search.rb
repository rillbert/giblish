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
    @index = {}
  end

  def grep(base_dir)
    # This console code sequence will only show the matching word in bold ms=01:mc=:sl=:cx=:fn=:ln=:bn=:se=
    grep_env="GREP_COLORS=\"ms=01:mc=:sl=:cx=:fn=:ln=:bn=:se=\""
    @grep_opts += " --color=always"
    puts "running: #{grep_env} grep #{@grep_opts} #{@input} #{@top_dir}"

    @output, @error, @status = Open3.capture3("#{grep_env} grep #{@grep_opts} #{@input} #{@top_dir}")
    reindex_result base_dir
  end

  # returns an indexed output where each match from the search is associated with the
  # corresponding src file's closest heading.
  # the format of the output:
  # {html_filename#heading : [line_1, line_2, ...], ...}
  #
  # src_index has format:
  # {filename_1 : {id_1 : line_no, id_2 : line_no, ...}, filename_2 ...}
  def index_output src_index
    output_index = {}
    @index.each do |k,v|
      if src_index.key?(k.to_s)
        file_anchors = index_one_file k,v,src_index[k.to_s]
        output_index = output_index.merge(file_anchors)
      end
    end
    output_index
  end

  def index_one_file filename, match_line_info_array,src_sections
    anchor_hash = {}
    match_line_info_array.each do |line_info|
      match_line_nr = line_info.line_no

      # find section with closest lower line_no to line_info
      best_so_far = 1
      chosen_id = ""
      src_sections.each do |id,line_no|
        l = Integer(line_no)
        if l <= match_line_nr && l > best_so_far
          best_so_far = l
          chosen_id = id
        end
      end

      # construct the location as filename#section_id
      anchor = "#{filename.sub_ext(".html").to_s}##{chosen_id}"

      # add hash[location] [<< line_n]
      anchor_hash[anchor] = [] unless anchor_hash.key? anchor
      anchor_hash[anchor] << line_info.line
    end
    anchor_hash
  end

  def formatted_output
    # assume we have an updated index
    adoc_str = ""
    @index.each do |k,v|
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
    @index = {}
    @output.split("\n").each do |line|
      tokens = line.split(":",3)
      file_path = Pathname.new(tokens[0]).relative_path_from Pathname.new(base_dir)
      @index[file_path] = [] unless @index.key? file_path
      @index[file_path] << Line_info.new(tokens[2],tokens[1])
    end
  end
end

# index have format
# {html_filename#heading : [line_1, line_2, ...], ...}
def format_search_adoc index
  <<~ADOC
  = Search Result

  #{str = ""
    index.each do |heading,lines|
      str << "#{heading}::\n"
      lines.each do |line|
        str << line
        str << "\n\n"
      end
      str << "\n"
    end
  str
  }

  ADOC
end

require 'benchmark'

# test the class...
if __FILE__ == $PROGRAM_NAME
#  cgi = CGI.new

  base_dir = "/home/anders/vironova/repos/qms"
  gt = nil
  # read in the src_index
  jsonpath = Pathname.new("/home/anders/repos/gendocs/heading_index.json").to_s
  puts "read json data from #{jsonpath}"
  src_index = {}
  json = File.read(jsonpath)
  src_index = JSON.parse(json)

  # search the doc tree for regex
  time = Benchmark.measure {
    gt = GrepDocTree.new "#{base_dir}/qms","Sentinel",true
    gt.grep base_dir
  }

  output = gt.index_output src_index

  docstr = <<~ADOC
  = Search Result


  #{puts output.inspect}

  ADOC

  puts format_search_adoc output
#  print cgi.header
#  print Asciidoctor.convert docstr, header_footer: true

  puts "\n===\n"
  puts time
end

# cgi = CGI.new
#
#
# docstr = <<~ADOC
# = A dynamically made doc
# :toc: left
# :numbered:
#
# == The query params
#
# I got #{cgi.keys}
#
# grep returns
#
# #{o}
# ADOC
#
#
# print cgi.header
# print Asciidoctor.convert docstr, header_footer: true
