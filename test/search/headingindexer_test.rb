# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/giblish/search/headingindexer"

module Giblish
  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/AbcSize
  class TestHeadingIndexer < Minitest::Test
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

    def setup_directories
      TmpDocDir.open do |tmp_doc_dir|
        root_dir = tmp_doc_dir.dir
        src_dir = Pathname.new(root_dir) / "src"
        paths = [@@doc_1, @@doc_2].map { |d| tmp_doc_dir.add_doc_from_str(d, "src") }
        dst_dir = Pathname.new(root_dir) / "dst"
        dst_dir.mkpath

        yield(src_dir, dst_dir, paths)
      end
    end

    def test_collect_search_data
      setup_directories do |src_dir, dst_dir, doc_paths|
        #  act on the input data
        args = ["-m",
          src_dir,
          dst_dir.to_s]
        Giblish.application.run args

        search_root = dst_dir.join("search_assets")
        assert Dir.exist?(search_root.to_s)

        # assert that the searchable index has been created
        assert File.exist?(search_root.join("heading_index.json"))

        # assert that the adoc src files have been copied to the
        # dst
        doc_paths.each do |doc|
          assert File.exist?(search_root.join(doc))
        end
      end
    end

    def test_custom_attributes
      setup_directories do |src_dir, dst_dir, doc_paths|
        #  act on the input data
        args = ["-m",
          "-a", "idprefix=argh",
          "-a", "idseparator=:",
          src_dir,
          dst_dir.to_s]
        Giblish.application.run args

        search_root = dst_dir.join("search_assets")
        assert Dir.exist?(search_root.to_s)

        # assert that the searchable index has been created
        assert File.exist?(search_root.join("heading_index.json"))

        # assert that the adoc src files have been copied to the
        # dst
        doc_paths.each do |doc|
          assert File.exist?(search_root.join(doc))
        end
      end
    end
  end
end
