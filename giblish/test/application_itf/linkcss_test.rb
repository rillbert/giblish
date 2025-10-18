require_relative "../test_helper"
require_relative "../../lib/giblish"

module Giblish
  class LinkCSSTest < GiblishTestBase
    include Giblish::TestUtils

    TEST_DOC = {
      doc_src: <<~EOF,
        = Test css linking
        :numbered:
        
        == My First Section

        Some dummy text....
        
        == My Second Section

        Some more dummy text...
        
      EOF
      subdir: "subdir_1"
    }

    def setup_dirs(top_dir)
      srcdir = Pathname.new(top_dir) / "src"
      dstdir = Pathname.new(top_dir) / "dst"
      r_dir = Pathname.new(top_dir) / "resources"
      copy_test_resources(r_dir)
      [srcdir, dstdir, r_dir]
    end

    # test that the css link is a relative link to the css file in the
    # local file system when user does not give web path
    #
    # giblish -r <resource_dir> src dst
    # shall yield:
    # dst
    # |- subdir
    # |    |- file.html (href ../web_assets/css/giblish.css)
    # |- web_assets
    # |    |- css
    #          |- giblish.css
    def test_custom_styling_without_webroot
      TmpDocDir.open(preserve: true) do |tmp_docs|
        srcdir, dstdir, r_dir = setup_dirs(tmp_docs.dir)

        # create a doc in the 'subdir' folder.
        tmp_docs.create_adoc_src_on_disk(srcdir, TEST_DOC)

        args = ["--log-level", "info",
          "-r", r_dir.to_s,
          "-s", "giblish",
          srcdir,
          dstdir]
        Giblish.application.run args

        dt = Gran::PathTree.build_from_fs(dstdir, prune: false)
        assert(1, dt.match(/web_assets$/).leave_pathnames.count)

        # filter out only html files
        dt = dt.match(/.html$/)
        assert(3, dt.leave_pathnames.count)
        expected_css = Pathname.new("web_assets/web/giblish.css")

        # assert that the css link is relative to the specific
        # css file (../web_assets/css/giblish.css)
        tmp_docs.get_html_dom(dt) do |node, document|
          next if /web_assets/.match?(node.pathname.to_s)

          # get the expected relative path from the top dst dir
          rp = dt.relative_path_from(node).dirname.join(expected_css)

          css_links = document.xpath("html/head/link")
          assert((1..2).cover?(css_links.count))

          css_links.each do |csslink|
            href = csslink.get("href")
            next if /font-awesome/.match?(href)

            assert_equal("stylesheet", csslink.get("rel"))
            assert_equal(rp.to_s, href)
          end
        end
      end
    end

    # test that the css link is a relative link to the css file
    # giblish -w /my/stylesheet/path
    def test_custom_styling_with_server_css_path
      TmpDocDir.open do |tmp_docs|
        srcdir, dstdir = setup_dirs(tmp_docs.dir)
        server_css = Pathname("/my/css/custom.css")

        # create a doc in the 'subdir' folder.
        tmp_docs.create_adoc_src_on_disk(srcdir, TEST_DOC)

        # run conversion
        args = ["--log-level", "info",
          "--server-css-path", server_css.to_s,
          srcdir,
          dstdir]
        Giblish.application.run args

        dt = Gran::PathTree.build_from_fs(dstdir, prune: false)
        assert_nil(dt.match(/web_asset/))
        assert_equal(3, dt.leave_pathnames.count)

        tmp_docs.get_html_dom(dt) do |node, document|
          next if /index.html/.match?(node.pathname.to_s)

          css_links = document.xpath("html/head/link")

          # we expect a css link to our custom stylesheet path and
          # another to font awesome (:icons: font is a default attribute)
          expected_links = [
            "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.min.css",
            server_css.to_s
          ]

          assert_equal expected_links.count, css_links.count

          css_links.each do |csslink|
            css_path = csslink.get("href")
            assert_equal("stylesheet", csslink.get("rel"))
            assert(expected_links.include?(css_path))
          end
        end
      end
    end
  end
end
