require_relative "test_helper"
require_relative "../lib/giblish/treeconverter"
require_relative "../lib/giblish/pathtree"

module Giblish
  class TreeConverterTest < Minitest::Test
    include Giblish::TestUtils

    def setup
      # setup logging
      Giblog.setup
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

    def test_generate_html
      TmpDocDir.open do |tmp_docs|
        # create three adoc files under .../src and .../src/subdir
        ["src", "src", "src/subdir"].each { |d| tmp_docs.add_doc_from_str(CreateAdocDocSrc.new, d) }

        # setup the corresponding PathTree
        p = Pathname.new(tmp_docs.dir)
        fs_root = tree_from_src_dir(p / "src")

        # find the PathTree node pointing to the "src" dir
        st = fs_root.node(p / "src", from_root: true)

        assert_equal(3, st.leave_pathnames.count)

        # init a converter that use ".../src" as the top dir,
        # and generates html to ".../dst"
        tc = TreeConverter.new(st, p / "dst")
        tc.run

        # get the node in the dst tree that points to .../dst
        dt = tc.dst_tree.node(p / "dst", from_root: true)

        # assert that there now are 3 html files under "dst"
        assert_equal(3, dt.leave_pathnames.count)
        assert_equal(
          st.leave_pathnames.collect { |p| p.sub_ext(".html").relative_path_from(st.pathname) },
          dt.leave_pathnames.collect { |p| p.relative_path_from(dt.pathname) }
        )
      end
    end

    def test_generate_html_docs_from_str
      TmpDocDir.open do |tmp_docs|
        p = Pathname.new(tmp_docs.dir)

        # setup a 'virtual' PathTree using strings as content for the nodes
        root = PathTree.new(p / "src/metafile_1", AdocFromString.new(CreateAdocDocSrc.new))
        root.add_path(p / "src/metafile_2", AdocFromString.new(CreateAdocDocSrc.new))
        root.add_path(p / "src/subdir/metafile_3", AdocFromString.new(CreateAdocDocSrc.new))

        st = root.node(p / "src", from_root: true)

        assert_equal(3, st.leave_pathnames.count)

        tc = TreeConverter.new(st, p / "dst")
        tc.run

        # get the node in the dst tree that points to .../dst
        dt = tc.dst_tree.node(p / "dst", from_root: true)

        # assert that there now are 3 html files under "dst"
        assert_equal(3, dt.leave_pathnames.count)
        assert_equal(
          st.leave_pathnames.collect { |p| p.sub_ext(".html").relative_path_from(st.pathname) },
          dt.leave_pathnames.collect { |p| p.relative_path_from(dt.pathname) }
        )
      end
    end

    def test_generate_pdf
      TmpDocDir.open do |tmp_docs|
        # create three adoc files under .../src and .../src/subdir
        ["src", "src", "src/subdir"].each { |d| tmp_docs.add_doc_from_str(CreateAdocDocSrc.new, d) }

        # setup the corresponding PathTree
        p = Pathname.new(tmp_docs.dir)
        fs_root = tree_from_src_dir(p / "src")

        # find the PathTree node pointing to the "src" dir
        st = fs_root.node(p / "src", from_root: true)

        assert_equal(3, st.leave_pathnames.count)

        # init a converter that use ".../src" as the top dir,
        # and generates html to ".../dst"
        tc = TreeConverter.new(st, p / "dst",
          {
            adoc_api_opts: {
              backend: "pdf"
            }
          }
        )
        tc.run

        # get the node in the dst tree that points to .../dst
        dt = tc.dst_tree.node(p / "dst", from_root: true)

        # assert that there now are 3 html files under "dst"
        assert_equal(3, dt.leave_pathnames.count)
        assert_equal(
          st.leave_pathnames.collect { |p| p.sub_ext(".pdf").relative_path_from(st.pathname) },
          dt.leave_pathnames.collect { |p| p.relative_path_from(dt.pathname) }
        )
      end
    end

    def test_generate_epub
      TmpDocDir.open do |tmp_docs|
        # create three adoc files under .../src and .../src/subdir
        ["src", "src", "src/subdir"].each { |d| tmp_docs.add_doc_from_str(CreateAdocDocSrc.new, d) }

        # setup the corresponding PathTree
        p = Pathname.new(tmp_docs.dir)
        fs_root = tree_from_src_dir(p / "src")

        # find the PathTree node pointing to the "src" dir
        st = fs_root.node(p / "src", from_root: true)

        assert_equal(3, st.leave_pathnames.count)

        # init a converter that use ".../src" as the top dir,
        # and generates html to ".../dst"
        tc = TreeConverter.new(st, p / "dst",
          {
            adoc_api_opts: {
              backend: "docbook5"
            }
          }
        )
        tc.run

        # get the node in the dst tree that points to .../dst
        dt = tc.dst_tree.node(p / "dst", from_root: true)

        # assert that there now are 3 html files under "dst"
        assert_equal(3, dt.leave_pathnames.count)
        assert_equal(
          st.leave_pathnames.collect { |p| p.sub_ext(".xml").relative_path_from(st.pathname) },
          dt.leave_pathnames.collect { |p| p.relative_path_from(dt.pathname) }
        )
      end
    end
  end
end
