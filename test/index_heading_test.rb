require "test_helper"
require "asciidoctor"
require "asciidoctor-pdf"
require_relative "../lib/giblish/indexheadings.rb"



class IndexHeadingTest < Minitest::Test

  # a common set of converter options used for all output formats
  COMMON_CONVERTER_OPTS = {
      safe: Asciidoctor::SafeMode::UNSAFE,
      header_footer: true,
      mkdirs: true
  }.freeze

  # the giblish attribute defaults used if nothing else
  # is required by the user
  DEFAULT_ATTRIBUTES = {
      "source-highlighter" => "rouge",
      "xrefstyle" => "short"
  }.freeze

  def setup
    # setup logging
    Giblog.setup

    # register the extension
    Giblish.register_index_heading_extension

    # find test directory path
    @testdir_path = File.expand_path(File.dirname(__FILE__))

    @src_root = "#{@testdir_path}/../data/testdocs"
    @dst_root = "#{@testdir_path}/../testoutput"
    FileUtils.mkdir_p @dst_root

    # Instanciate a path manager with
    # source root ==  .../giblish/data/testdocs and
    # destination root == .../giblish/test/testoutput
    @paths = Giblish::PathManager.new(@src_root,
                                      @dst_root)

    @converter_options = COMMON_CONVERTER_OPTS.dup
    @converter_options[:fileext] = "html"

  end

  def test_indexing

    filepath = "#{@src_root}/wellformed/index_headings/simple_test.adoc"

    # create an asciidoc doc object and convert to requested
    # output using current conversion options
    @converter_options[:to_dir] = @paths.adoc_output_dir(filepath).to_s
    @converter_options[:base_dir] =
        Giblish::PathManager.closest_dir(filepath).to_s
    @converter_options[:to_file] =
        Giblish::PathManager.get_new_basename(filepath,
                                              @converter_options[:fileext])

    # do the actual conversion
    Asciidoctor.convert_file "#{filepath}", @converter_options

  end
end
