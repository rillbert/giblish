#!/usr/bin/env ruby

require "pathname"
require "asciidoctor"
require "open3"
require "cgi"

class GrepDocTree
  def initialize(top_dir, input_str, is_case_sensitive = true)
    @grep_opts = "-nHr"
    @grep_opts += "i" unless is_case_sensitive
    @grep_opts += " --include '*.adoc'"
    @top_dir = Pathname.new top_dir
    @input = input_str
    @output = ""
    @error = ""
    @status = 0
  end

  def grep
    # This console code sequence will only show the matching word in bold ms=01:mc=:sl=:cx=:fn=:ln=:bn=:se=
    grep_env="GREP_COLORS=\"ms=01:mc=:sl=:cx=:fn=:ln=:bn=:se=\""
    @grep_opts += " --color=always"
    puts "running: #{grep_env} grep #{@grep_opts} #{@input} #{@top_dir}"

    @output, @error, @status = Open3.capture3("#{grep_env} grep #{@grep_opts} #{@input} #{@top_dir}")
  end

  def formatted_output
    # grep format is
    # <filename>:<line_no>:<line>
    adoc_str = ""
    @output.split("\n").each do |line|
      tokens = line.split(":",3)
      adoc_str += "#{tokens[0]} - line #{tokens[1]}::\n"
      adoc_str += "_#{tokens[2]}_\n\n"
    end
    adoc_str
  end
end


# test the class...
if __FILE__ == $PROGRAM_NAME
  cgi = CGI.new

  gt = GrepDocTree.new "/home/anders/vironova/repos/qms/qms","process",true
  gt.grep

  docstr = <<~ADOC
  = Search Result

  == Searching for #{cgi["search"]}

  #{gt.formatted_output}
  ADOC

  print cgi.header
  print Asciidoctor.convert docstr, header_footer: true
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
