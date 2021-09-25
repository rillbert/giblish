#!/usr/bin/env ruby

require "asciidoctor"
require "cgi"
require_relative "../gh_giblish/lib/giblish/search/request_manager"

def init_web_server web_root
  require "webrick"

  root = File.expand_path web_root
  puts "Trying to start a WEBrick instance at port 8000 serving files from #{web_root}..."

  server = WEBrick::HTTPServer.new(
    Port: 8000,
    DocumentRoot: root,
    Logger: WEBrick::Log.new("webrick.log", WEBrick::Log::DEBUG)
  )

  puts "WEBrick instance now listening to localhost:8000"

  trap "INT" do
    server.shutdown
  end

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

def search_response(cgi)
  rm = Giblish::CGIRequestManager.new(cgi, {"/" => "/home/andersr/repos/gendocs"})
  print rm.response
end


def cgi_main(cgi, debug_mode = false)
  # retrieve the form data supplied by user
  input_data = {
    search_phrase: cgi["search-phrase"],
    ignorecase: cgi.has_key?("ignorecase"),
    useregexp: cgi.has_key?("useregexp"),
    searchassetstop: Pathname.new(
      cgi.has_key?("searchassetstop") ? cgi["searchassetstop"] : ""
    ),
    webassetstop: Pathname.new(
      cgi.has_key?("webassetstop") ? cgi["webassetstop"] : nil
    ),
    client_css:
          cgi.has_key?("css") ? cgi["css"] : nil,
    referer: cgi.referer
  }

  if input_data[:searchassetstop].nil? || !Dir.exist?(input_data[:searchassetstop])
    raise ScriptError, "Could not find search_assets dir (#{input_data[:searchassetstop]}) !"
  end

  adoc_attributes = {
    "data-uri" => 1
  }

  # Set attributes so that the generated result page uses the same
  # css as the other docs
  if !input_data[:client_css].nil? && !input_data[:webassetstop].nil?
    adoc_attributes.merge!(
      {
        "linkcss" => 1,
        "stylesdir" => "#{input_data[:webassetstop]}/css",
        "stylesheet" => input_data[:client_css],
        "copycss!" => 1
      }
    )
  end

  converter_options = {
    backend: "html5",
    # need this to let asciidoctor include the default css if user
    # has not specified any css
    safe: Asciidoctor::SafeMode::SAFE,
    header_footer: true,
    attributes: adoc_attributes
  }

  # search the docs and render html
  sdt = SearchDocTree.new(input_data)
  docstr = sdt.search

  if debug_mode
    # print some useful data for debugging
    docstr = <<~EOF

      == Input data

      #{input_data}

      == Adoc attributes

       #{adoc_attributes}

       #{docstr}
    EOF
  end

  # send the result back to the client
  print Asciidoctor.convert(docstr, converter_options)
end

# Usage:
#   to start a local web server for development work
# ruby gibsearch.cgi <web_root>
#
#   to run as a cgi script via a previously setup web server
# gibsearch.cgi
#
if __FILE__ == $PROGRAM_NAME

  STDOUT.sync = true
  if ARGV.length == 0
    # 'Normal' cgi usage, as called from a web server

    # init a new cgi 'connection' and print headers
    cgi = CGI.new

    print cgi.header
    # print "\n-----\n"
    # print cgi.class

    begin
      # hello_world
      search_response(cgi)
    rescue => e
      print e.message
      print ""
      print e.backtrace
      exit 1
    end
    exit 0
  end

  if ARGV.length == 1
    # Run a simple web server to test this locally..
    # and then create the html docs using:
    # giblish -c -m -w <web_root> -r <resource_dir> -s <style_name> -g <git_branch> <src_root> <web_root>
    init_web_server(ARGV[0])
    exit 0
  end
end
