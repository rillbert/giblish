require_relative "../test_helper"
require_relative "../../lib/giblish/treeconverter"
require_relative "../../lib/giblish/pathtree"
require_relative "../../lib/giblish/indexbuilders/buildindex"

module Giblish
  class BasicIndexTest < Minitest::Test
    include Giblish::TestUtils

    def setup
      # setup logging
      Giblog.setup
    end

    def teardown
      # need to unregister the docid extension between subsequent tests
      Asciidoctor::Extensions.unregister_all
    end

    def tree_from_src_dir(top_dir)
      src_tree = PathTree.build_from_fs(top_dir, prune: false) do |pt|
        !pt.directory? && pt.extname == ".adoc"
      end
      src_tree.traverse_preorder do |level, n|
        next unless n.leaf?

        n.data = AdocSrcFromFile.new(n)
      end
      src_tree
    end

    def test_generate_index_default_style
      TmpDocDir.open(preserve: true) do |tmp_docs|
        # create three adoc files under .../src and .../src/subdir
        ["src", "src", "src/subdir"].each { |d| puts tmp_docs.add_doc_from_str(CreateAdocDocSrc.new, d) }

        # setup the corresponding PathTree
        p = Pathname.new(tmp_docs.dir)
        fs_root = tree_from_src_dir(p / "src")

        # find the PathTree node pointing to the "src" dir
        st = fs_root.node(p / "src", from_root: true)

        assert_equal(3, st.leave_pathnames.count)

        # Convert all adoc files in the src tree to html and use s
        # 'post builder' to generate adoc source for index pages for each
        # directory.
        index_builder = IndexTreeBuilder.new(p / "dst")
        tc = TreeConverter.new(st, p / "dst", {post_builders: index_builder})
        tc.run

        # get the node in the dst tree that points to .../dst
        dt = tc.dst_tree.node(p / "dst", from_root: true)

        # assert that there now are 2 index files under "dst"
        assert_equal(5, dt.leave_pathnames.count)
        count = 0
        dt.leave_pathnames.each { |p| count += 1 if "index.html" == p.basename.to_s }
        assert_equal(2, count)
      end
    end

    def test_generate_index_linked_css
      TmpDocDir.open(preserve: false) do |tmp_docs|
        # create three adoc files under .../src and .../src/subdir
        ["src", "src", "src/subdir"].each { |d| tmp_docs.add_doc_from_str(CreateAdocDocSrc.new, d) }

        # Build a PathTree using the 'src' dir as root
        p = Pathname.new(tmp_docs.dir)
        fs_root = tree_from_src_dir(p / "src")

        # find the PathTree node pointing to the "src" dir
        st = fs_root.node(p / "src", from_root: true)

        assert_equal(3, st.leave_pathnames.count)

        # setup a post-builder to build index pages in each dir using a relative
        # css path
        css_path = "web_assets/hejsan/hopp.css"
        index_builder = IndexTreeBuilder.new(
          p / "dst",
          RelativeCss.new(p / "dst" / css_path)
        )

        # Convert all adoc files in the src tree to html and use the
        # post builder for indices
        tc = TreeConverter.new(st, p / "dst", {
          post_builders: index_builder
        })
        tc.run

        # filter out the 'index.html' files in a new tree
        it = tc.dst_tree.filter(/.*index.html$/)
        it = it.node(p / "dst", from_root: true)

        # assert that there now are 2 index files under "dst"
        assert_equal(2, it.leave_pathnames.count)

        # assert that the css link is relative to the specific
        # css file (../web_assets/css/giblish.css)
        tmp_docs.get_html_dom(it) do |n, doc_dom|
          css_links = doc_dom.xpath("html/head/link")
          assert_equal 2, css_links.count

          # assert the href correspond to the relative path
          css_links.each do |csslink|
            next if csslink.get("href").start_with?("https://cdnjs.cloudflare.com")

            assert_equal "stylesheet", csslink.get("rel")

            # get the expected relative path from the top dst dir
            rp = it.pathname.relative_path_from(n.pathname.dirname) / css_path
            # rp = Pathname.new(css_path).relative_path_from(
            #   (stem.basename + crown)
            # )

            assert_equal rp.to_s,
              csslink.get("href")
          end
        end
      end
    end

    def test_generate_index_pdf
      TmpDocDir.open(preserve: false) do |tmp_docs|
        # create three adoc files under .../src and .../src/subdir
        ["src", "src", "src/subdir"].each { |d| puts tmp_docs.add_doc_from_str(CreateAdocDocSrc.new, d) }

        # setup the corresponding PathTree
        p = Pathname.new(tmp_docs.dir)

        fs_root = tree_from_src_dir(p / "src")

        # find the PathTree node pointing to the "src" dir
        st = fs_root.node(p / "src", from_root: true)

        # setup a post builder to generate pdf index pages for each dir
        index_builder = IndexTreeBuilder.new(
          p / "dst",
          PdfCustomStyle.new(p / "resources/themes/giblish.yml")
        )

        # Convert all adoc files in the src tree to pdf
        tc = TreeConverter.new(st, p / "dst",
          {
            adoc_api_opts: {
              backend: "pdf"
            },
            post_builders: index_builder
          })
        tc.run

        # filter out the 'index.pdf' files in a new tree
        it = tc.dst_tree.filter(/.*index.pdf$/)
        it = it.node(p / "dst", from_root: true)

        assert_equal(2, it.leave_pathnames.count)
      end
    end
  end
end
