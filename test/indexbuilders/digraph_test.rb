require "asciidoctor"
require "test_helper"
require_relative "../../lib/giblish/indexbuilders/digraphindex"
require_relative "../../lib/giblish/pathtree"

module Giblish
  class DigraphTest < Minitest::Test
    include Giblish::TestUtils

    @@test_doc_1 = <<~EOF
      = Test digraph
      :numbered:
      :docid: D-1
      
      == A section

      A ref to <<:docid:D-2,Doc 2>>
      
    EOF

    @@test_doc_2 = <<~EOF
      = Test digraph
      :numbered:
      :docid: D-2
      
      == A section

      A ref to <<:docid:D-1,Doc 1>>
      
    EOF

    def setup
      # DocidCollector.docid_cache = {
      #   "D-1" => Pathname.new("docs/doc_1.adoc"),
      #   "D-2" => Pathname.new("docs/doc_2.adoc")
      # }

      Giblog.setup
      # Register the docid preprocessor hook
      Asciidoctor::Extensions.register do
        preprocessor DocidCollector
      end
    end

    def teardown
      DocidCollector.docid_cache = {}
    end

    def test_create_digraph_src
      TmpDocDir.open do |tmp_docs|
        # setup relevant paths
        paths = Giblish::PathManager.new(tmp_docs.dir, tmp_docs.dir, nil, false)
        docinfo_store = DocInfoStore.new(paths)

        # create files from the test strings
        adoc1_filename = tmp_docs.add_doc_from_str(@test_doc_1)
        # adoc2_filename = tmp_docs.add_doc_from_str(@test_doc_2)

        # build a fake doc tree with DocInfo instances as
        # node data
        doc1 = Asciidoctor.load_file(adoc1_filename, safe: "unsafe")
        docinfo_store.add_success(doc1, nil)
        d = DigraphIndex.new(docinfo_store.pathtree)
      end
    end
  end
end
