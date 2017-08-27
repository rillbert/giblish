require "test_helper"
require_relative "../lib/giblish/utils.rb"
require_relative "../lib/giblish/docid.rb"

class DocidCollectorTest < Minitest::Test
  def setup
    # setup logging
    Giblog.setup

    # find test directory path
    @testdir_path = File.expand_path(File.dirname(__FILE__))

    # Instanciate a path manager with
    # source root ==  .../giblish/data/testdocs and
    # destination root == .../giblish/test/testoutput
    @paths = Giblish::PathManager.new("#{@testdir_path}/../data/testdocs",
                                      "#{@testdir_path}/testoutput")
  end

  def test_collect_docids
    args = ["--log-level",
            "debug",
            "#{@testdir_path}/../data/testdocs",
            "#{@testdir_path}/testoutput"]
    Giblish.application.run_with_args args

#    src_root_path = @paths.src_root_abs + "wellformed/docidtest"
    src_root_path = @paths.src_root_abs

    # traverse the src file tree and collect ids from all
    # .adoc or .ADOC files
    Find.find(src_root_path) do |path|
      ext = File.extname(path)
      idc.parse_file(path) if !ext.empty? && ext.casecmp(".ADOC").zero?
    end

    # do pass two and substitute :docid: tags
    Find.find(src_root_path) do |path|
      ext = File.extname(path)
      next if ext.empty? || !ext.casecmp(".ADOC").zero?
      processed_str = idc.substitute_ids_file(path)

      Giblog.logger.debug {"path: #{path}"}
      # load and convert the document using the converter options
      doc = Asciidoctor.load processed_str
      output = doc.convert
      puts output

      # write the converted document to an index file located at the
      # destination root
      p = Pathname(path)
      output_file_name = p.dirname + "#{p.basename.to_s.gsub(/.adoc/,".html")}"
      doc.write output, output_file_name.to_s
    end
  end
end
