require_relative "../test_helper"
require_relative "../../lib/giblish/search/headingindexer"

module Giblish
  class TestHeadingIndexer < GiblishTestBase
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

    def setup_directories
      TmpDocDir.open do |tmp_doc_dir|
        topdir = Pathname.new(tmp_doc_dir.dir)
        src_dir = topdir / "src"
        dst_dir = topdir / "dst"
        dst_dir.mkpath

        paths = []
        paths += tmp_doc_dir.create_adoc_src_on_disk(src_dir, {doc_src: @@doc_1})
        paths += tmp_doc_dir.create_adoc_src_on_disk(src_dir, {doc_src: @@doc_2, subdir: "subdir"})

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

        search_root = dst_dir.join(HeadingIndexer::SEARCH_ASSET_DIRNAME)
        assert Dir.exist?(search_root.to_s)

        # assert that the searchable index has been created
        assert File.exist?(search_root.join(HeadingIndexer::HEADING_DB_BASENAME))

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

        search_root = dst_dir.join(HeadingIndexer::SEARCH_ASSET_DIRNAME)
        assert Dir.exist?(search_root.to_s)

        # assert that the searchable index has been created
        assert File.exist?(search_root.join(HeadingIndexer::HEADING_DB_BASENAME))

        # assert that the adoc src files have been copied to the
        # dst
        doc_paths.each do |doc|
          assert File.exist?(search_root.join(doc))
        end
      end
    end
  end
end
