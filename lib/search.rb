#!/usr/bin/env ruby

require "pathname"
require "asciidoctor"
require "open3"
require "cgi"

class GrepDocTree
  Line_info = Struct.new(:line_no, :line)

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

  def reindex_result(base_dir)
    # grep format is
    # <filename>:<line_no>:<line>
    @index = {}
    @output.split("\n").each do |line|
      tokens = line.split(":",3)
      file_path = Pathname.new(tokens[0]).relative_path_from Pathname.new(base_dir)
      @index[file_path] = [] unless @index.key? file_path
      @index[file_path] << Line_info.new(tokens[1],tokens[2])
    end
  end
end


require 'benchmark'

# test the class...
if __FILE__ == $PROGRAM_NAME
  cgi = CGI.new

  base_dir = "/home/anders/vironova/repos/qms"
  gt = nil
  time = Benchmark.measure {
    gt = GrepDocTree.new "#{base_dir}/qms","Sentinel",true
    gt.grep base_dir
  }

  docstr = <<~ADOC
  = Search Result

  == Searching for #{cgi["search"]}

  #{gt.formatted_output}
  ADOC

  puts docstr
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
