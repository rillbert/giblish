require_relative "../test_helper"
require_relative "../../lib/giblish/treeconverter"
require_relative "../../lib/giblish/pathtree"
require_relative "../../lib/giblish/subtreeinfobuilder"
require_relative "../../lib/giblish/indexbuilders/subtree_indices"

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

        n.data = SrcFromFile.new
      end
      src_tree
    end

    def test_generate_index_default_style
      TmpDocDir.open(preserve: false) do |tmp_docs|
        srcdir = Pathname.new(tmp_docs.dir) / "src"
        dstdir = Pathname.new(tmp_docs.dir) / "dst"

        # create three adoc files under .../src and .../src/subdir
        tmp_docs.create_adoc_src_on_disk(srcdir, {}, {}, {subdir: "subdir"})

        # setup the corresponding PathTree
        src_tree = tree_from_src_dir(srcdir)
        assert_equal(3, src_tree.leave_pathnames.count)

        # Convert all adoc files in the src tree to html and use a
        # 'post builder' to generate adoc source for index pages for each
        # directory.
        index_builder = SubtreeInfoBuilder.new(nil, nil, SubtreeIndexBase, "index")
        tc = TreeConverter.new(src_tree, dstdir, {post_builders: index_builder})
        tc.run

        # get the node in the dst tree that points to .../dst
        dt = tc.dst_tree.node(dstdir, from_root: true)

        # assert that there now are 2 index files under "dst"
        assert_equal(5, dt.leave_pathnames.count)
        count = 0
        dt.leave_pathnames.each { |p| count += 1 if p.basename.to_s == "index.html" }
        assert_equal(2, count)
      end
    end

    def test_generate_index_when_dir_basename_same_as_file
      TmpDocDir.open(preserve: false) do |tmp_docs|
        srcdir = Pathname.new(tmp_docs.dir) / "src"
        dstdir = Pathname.new(tmp_docs.dir) / "dst"

        # create a file and dir with same basename
        tmp_docs.create_file(srcdir / "mydir.adoc")
        tmp_docs.create_file(srcdir / "mydir/myfile.adoc")

        # setup the corresponding PathTree
        src_tree = tree_from_src_dir(srcdir)

        # Convert all adoc files in the src tree to html and use a
        # 'post builder' to generate adoc source for index pages for each
        # directory.
        index_builder = SubtreeInfoBuilder.new(nil, nil, SubtreeIndexBase, "index")
        tc = TreeConverter.new(src_tree, dstdir, {post_builders: index_builder})
        tc.run
        
        # get the node in the dst tree that points to .../dst
        dt = tc.dst_tree.node(dstdir, from_root: true)

        # assert that there are 4 files in total where 2 are index files
        assert_equal(4, dt.leave_pathnames.count)
        count = 0
        dt.leave_pathnames.each { |p| count += 1 if p.basename.to_s == "index.html" }
        assert_equal(2, count)
      end
    end

    def test_generate_index_linked_css
      TmpDocDir.open(preserve: false) do |tmp_docs|
        srcdir = Pathname.new(tmp_docs.dir) / "src"
        dstdir = Pathname.new(tmp_docs.dir) / "dst"

        # create three adoc files under .../src and .../src/subdir
        tmp_docs.create_adoc_src_on_disk(srcdir, {}, {}, {subdir: "subdir"})

        # setup the corresponding PathTree
        src_tree = tree_from_src_dir(srcdir)
        assert_equal(3, src_tree.leave_pathnames.count)

        # Convert all adoc files in the src tree to html and use the
        # post builder for indices
        css_path = "web_assets/hejsan/hopp.css"
        tc = TreeConverter.new(src_tree, dstdir, {
          post_builders: SubtreeInfoBuilder.new(RelativeCssDocAttr.new(css_path), nil, SubtreeIndexBase, "index")
        })
        tc.run

        # filter out the 'index.html' files in a new tree
        it = tc.dst_tree.match(/.*index.html$/)

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

            assert_equal rp.to_s,
              csslink.get("href")
          end
        end
      end
    end

    def test_generate_index_pdf
      TmpDocDir.open(preserve: false) do |tmp_docs|
        srcdir = Pathname.new(tmp_docs.dir) / "src"
        dstdir = Pathname.new(tmp_docs.dir) / "dst"

        # create three adoc files under .../src and .../src/subdir
        tmp_docs.create_adoc_src_on_disk(srcdir, {}, {}, {subdir: "subdir"})

        # setup the corresponding PathTree
        src_tree = tree_from_src_dir(srcdir)
        assert_equal(3, src_tree.leave_pathnames.count)

        # Convert all adoc files in the src tree to pdf
        # setup a post builder to generate pdf index pages for each dir
        tc = TreeConverter.new(src_tree, dstdir,
          {
            adoc_api_opts: {
              backend: "pdf"
            },

            post_builders: SubtreeInfoBuilder.new(nil, nil, SubtreeIndexBase, "index")
          })
        tc.run

        # filter out the 'index.pdf' files in a new tree
        it = tc.dst_tree.match(/.*index.pdf$/)

        assert_equal(2, it.leave_pathnames.count)
      end
    end
  end
end
