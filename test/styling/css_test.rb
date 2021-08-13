require_relative "../test_helper"
require_relative "../../lib/giblish/treeconverter"
require_relative "../../lib/giblish/converters"
require_relative "../../lib/giblish/pathtree"

module Giblish
  class CssStylingTest < Minitest::Test
    include Giblish::TestUtils

    def setup
      # setup logging
      Giblog.setup
    end

    def test_option_setup
      d = DataDelegator.new(RelativeCssDocAttr.new("hej"))
      assert(d.respond_to?(:document_attributes))
    end

    def test_embedded_default_styling
      TmpDocDir.open(preserve: true) do |tmp_docs|
        p = Pathname.new(tmp_docs.dir)

        # setup a 'virtual' PathTree using strings as content for the nodes
        root = PathTree.new("src/metafile_1", SrcFromString.new(CreateAdocDocSrc.new.source))
        root.add_path("src/metafile_2", SrcFromString.new(CreateAdocDocSrc.new.source))
        root.add_path("src/subdir/metafile_3", SrcFromString.new(CreateAdocDocSrc.new.source))

        tc = TreeConverter.new(root, p / "dst")
        tc.run

        # assert that the css link is relative to the specific
        # css file (../web_assets/css/giblish.css)
        tmp_docs.get_html_dom(tc.dst_tree) do |n, document|
          css_links = document.xpath("html/head/link")
          assert_equal 1, css_links.count

          # assert the href correspond to the one that exists in the default
          # asciidoctor stylesheet
          css_links.each do |csslink|
            assert_equal "stylesheet", csslink.get("rel")
            assert_equal "https://fonts.googleapis.com/css?family=Open+Sans:300,300italic,400,400italic,600,600italic%7CNoto+Serif:400,400italic,700,700italic%7CDroid+Sans+Mono:400,700",
              csslink.get("href")
          end
        end
      end
    end

    def test_linked_custom_css
      TmpDocDir.open do |tmp_docs|
        p = Pathname.new(tmp_docs.dir)

        # setup a 'virtual' PathTree using strings as content and
        # linked css as styling
        css_path = "dst/web_assets/hejsan/hopp.css"
        data_delegator = DataDelegator.new(
          RelativeCssDocAttr.new(p / css_path),
          SrcFromString.new(CreateAdocDocSrc.new.source)
        )

        root = PathTree.new("src/metafile_1", data_delegator)
        root.add_path("src/metafile_2", data_delegator)
        root.add_path("src/subdir/metafile_3", data_delegator)

        tc = TreeConverter.new(root, p / "dst")
        tc.run

        # assert that the css link is relative to the specific
        # css file (../web_assets/css/giblish.css)
        tmp_docs.get_html_dom(tc.dst_tree) do |n, document|
          css_links = document.xpath("html/head/link")
          assert_equal 1, css_links.count

          # get the expected relative path from the top dst dir
          stem, crown = n.split_stem
          rp = Pathname.new(css_path).relative_path_from(
            (stem.basename + crown)
          )

          # assert the href correspond to the relative path
          css_links.each do |csslink|
            assert_equal "stylesheet", csslink.get("rel")
            assert_equal rp.to_s,
              csslink.get("href")
          end
        end
      end
    end
  end
end
