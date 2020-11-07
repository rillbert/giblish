require "test_helper"
require "asciidoctor"
require "asciidoctor-pdf"
require_relative "../lib/giblish/indexheadings.rb"

class IndexHeadingTest < Minitest::Test
  include Giblish::TestUtils

  @@doc_1 = <<~EOF
    = Doc 1
    :numbered:

    == Section on animals
    
    This section mentions different animals, like elephant, crockodile
    and possum.

    == Section on plants

    Talks about birch, sunflowers, tulips and other stuff in the flora.
  EOF

  @@doc_2 = <<~EOF
    = Doc 2
    :numbered:

    [[a_custom_car_section_anchor]]
    == Section on cars

    Mentions things like Volvo, Mercedes and Skoda.

    == Section on boats

    Obsesses around yatches, steam boats and motor boats.
  EOF

  def setup
    Giblog.setup
  end

  def teardown
  end

  def test_create_search_index
    TmpDocDir.open() do |tmp_doc_dir|
      root_dir = tmp_doc_dir.dir
      # arrange input
      out_dir_path = Pathname.new(root_dir).join("output")
      Dir.mkdir(out_dir_path.to_s)
      doc_1 = tmp_doc_dir.add_doc_from_str @@doc_1
      doc_2 = tmp_doc_dir.add_doc_from_str @@doc_2

      # act on the input data
      args = ["-m",
              root_dir,
              out_dir_path.to_s]
      status = Giblish.application.run args


      assert_equal 0, status

      # assert that the searchable index has been created
      search_root = out_dir_path.join("search_assets")
      assert_equal true , Dir.exist?(search_root.to_s)
      assert_equal true , File.exist?(search_root.join("heading_index.json"))
      assert_equal true , File.exist?(search_root.join(doc_1))
      assert_equal true , File.exist?(search_root.join(doc_2))

      # assert stuff of the json contents
      # File.open(search_root.join("heading_index.json")).each do |l|
      #   puts l
      # end
    end
  end
end
