#!/usr/bin/env ruby

require "pathname"
require "json"
require "asciidoctor"
require "open3"
require "cgi"
require "uri/generic"

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
      best_so_far = 0
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

    format_search_adoc matches, get_uri_top
  end

  private

  def get_uri_top
    return @input_data[:referer][0,@input_data[:referer].rindex('/')]
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
  def format_search_adoc index,uri_top
    str = ""
    # debug print referer...
    # str << "uri_top: #{uri_top}\n"
    index.each do |file_info|
      filename = Pathname.new(file_info["filepath"]).basename
      str << "== #{file_info["title"]}\n\n"
      file_info["matches"].each do |section_id, info |
        str << "#{uri_top}/#{info["location"]}[#{info["section_title"]}]::\n\n"
        # str << "<<#{info["location"]},#{info["section_title"]}>>::\n\n"
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

  server = WEBrick::HTTPServer.new(
      :Port => 8000,
      :DocumentRoot => root,
      :Logger => WEBrick::Log.new("webrick.log",WEBrick::Log::DEBUG)
  )

  puts "WEBrick instance now listening to localhost:8000"

  trap 'INT' do server.shutdown end

  server.start
end

def hello_world
  require "pp"

  # init a new cgi 'connection'
  cgi = CGI.new
  print cgi.header
  print "<br>"
  print "Useful cgi parameters and variables."
  print "<br>"
  print cgi.public_methods(false).sort
  print "<br>"
  print "<br>"
  print "referer: #{cgi.referer}<br>"
  print "path: #{URI(cgi.referer).path}<br>"
  print "host: #{cgi.host}<br>"
  print "client_sent_topdir: #{cgi["topdir"]}<br>"
  print "<br>"
  print "client_sent_reldir: #{cgi["reltop"]}<br>"
  print "<br>"
  print "ENV: "
  pp ENV
  print "<br>"
end

def cgi_main cgi
  # retrieve the form data supplied by user
  input_data = {
      search_phrase: cgi["searchphrase"],
      ignorecase: cgi.has_key?("ignorecase"),
      useregexp: cgi.has_key?("useregexp"),
      doc_root_abs: Pathname.new(cgi["topdir"]),
      branch_dir: cgi["branchdir"],
      referer: cgi.referer,
      uri_path: URI(cgi.referer).path,
      client_css: cgi["css"],
      search_top: nil,
      styles_top: nil
  }

# assume that the file tree looks like this when rendering
# a git branch:
#
# root_dir
# |- index.html (the generated index of rendered git branches and tags)
# |- branch_1_top_dir
# |     |- index.html (the generated index of this branch)
# |     |- file_1.html
# |     |- dir_1
# |     |   |- file2.html
# |- branch_2_top_dir
# |- branch_x_...
# |- web_assets (only if a custom stylesheet is used...)
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
# root_dir
# |- index.html  (the generated index of all rendered files)
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
  # search_assets and styles_top shall be absolute paths
  #
  input_data[:styles_top] = input_data[:doc_root_abs].join("./web_assets/css")
   unless input_data[:styles_top].exist?
     raise ScriptError, "Could not find styles_top dir!"
   end

  input_data[:search_top] = input_data[:doc_root_abs].join("./search_assets")
  unless input_data[:branch_dir].nil?
    # this is from a git branch
    input_data[:search_top] = input_data[:search_top].join(input_data[:branch_dir])
  end
  unless input_data[:search_assets].exist?
    raise ScriptError, "Could not find search_assets dir!"
  end
  end

  # Set some reasonable default attributes and options
  adoc_attributes = {
      "data-uri" => 1,
  }

  converter_options = {
      backend: "html5",
      # need this to let asciidoctor include the default css if user
      # has not specified any css
      safe: Asciidoctor::SafeMode::SAFE,
      header_footer: true,
      attributes: adoc_attributes
  }

  # use the same stylesheet as the documents were rendered with.
  # if the script has received input in the client_css form field
  if !input_data[:client_css].nil? && !input_data[:client_css].empty?
    css_path = if input_data[:styles_top].to_s[0] != '/'
                 "/" + input_data[:styles_top].to_s
               else
                 input_data[:styles_top].to_s
               end
    adoc_attributes.merge!({
                            "linkcss" => 1,
                            "stylesdir" => css_path,
                            "stylesheet" => input_data[:client_css],
                            "copycss!" => 1
                        })
  end

  # search the docs and render html
  sdt = SearchDocTree.new(input_data)
  docstr = sdt.search

# used for debug purposes
#   docstr = <<~EOF
#
#     #{input_data[:referer_rel_top]} is branch: #{input_data[:gitbranch]}
#
#     #{adoc_attributes.to_s}
#
#
#     #{sdt.search}
#   EOF

  # send the result back to the client
  print Asciidoctor.convert(docstr, converter_options)
end


# Usage:
#   to start a local web server for development work
# giblish-search.rb <web_root>
#
#   to run as a cgi script via a previously setup web server
# giblish-search.rb
#
# (note that you might need to rename the script to eg
# giblish-search.cgi or similar depending on your web server
# setup)
#
if __FILE__ == $PROGRAM_NAME

  STDOUT.sync = true
  if ARGV.length == 0
    # 'Normal' cgi usage, as called from a web server

    # init a new cgi 'connection' and print headers
    cgi = CGI.new
    print cgi.header
    begin
      cgi_main cgi
    rescue Exception => e
      print e.message
      exit 1
    end
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
