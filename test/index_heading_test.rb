require "test_helper"
require "asciidoctor"
require "asciidoctor-pdf"
require_relative "../lib/giblish/indexheadings.rb"



class IndexHeadingTest < Minitest::Test
  include Giblish::TestUtils

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
    setup_log_and_paths

    # register the extension
    Giblish.register_index_heading_extension

    @converter_options = COMMON_CONVERTER_OPTS.dup
    @converter_options[:fileext] = "html"
  end

  def teardown
    teardown_log_and_paths dry_run: false
  end

  def test_indexing

    # filepath = "#{@src_root}/wellformed/index_headings/simple_test.adoc"
    #
    # # create an asciidoc doc object and convert to requested
    # # output using current conversion options
    # @converter_options[:to_dir] = @paths.adoc_output_dir(filepath).to_s
    # @converter_options[:base_dir] =
    #     Giblish::PathManager.closest_dir(filepath).to_s
    # @converter_options[:to_file] =
    #     Giblish::PathManager.get_new_basename(filepath,
    #                                           @converter_options[:fileext])
    #
    # # do the actual conversion
    # Asciidoctor.convert_file "#{filepath}", @converter_options

  end
end
