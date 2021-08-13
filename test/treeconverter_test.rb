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

        n.data = SrcFromFile.new
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
        root = PathTree.new(p / "src/metafile_1", SrcFromString.new(CreateAdocDocSrc.new.source))
        root.add_path(p / "src/metafile_2", SrcFromString.new(CreateAdocDocSrc.new.source))
        root.add_path(p / "src/subdir/metafile_3", SrcFromString.new(CreateAdocDocSrc.new.source))

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

    def test_adoc_logging
      TmpDocDir.open do |tmp_docs|
        # create three adoc files under .../src and .../src/subdir
        ["src", "src", "src/subdir"].each { |d| tmp_docs.add_doc_from_str(CreateAdocDocSrc.new, d) }
        p = Pathname.new(tmp_docs.dir)

        # write a non-conformant file to src
        File.write((p / "src/bad.adoc").to_s, <<~BAD_ADOC
          Badly formed doc

          === Out of level

          some text

        BAD_ADOC
        )
        # setup the corresponding PathTree
        fs_root = tree_from_src_dir(p / "src")

        # find the PathTree node pointing to the "src" dir
        st = fs_root.node(p / "src", from_root: true)

        # init a converter that use the standard Giblog logger for its
        # internal use but sets the asciidoc log level to only emit warnings
        # and above.
        # Supply callbacks that are called after each conversion
        tc = TreeConverter.new(st, p / "dst",
        {
          logger: Giblog.logger,
          adoc_log_level: Logger::WARN,
          conversion_cb: {
            success: ->(src,dst,dst_rel_path, doc,logstr) { 
              return unless dst.segment == "bad.html"

              # we know how the warning 'bad.adoc' should render.
              assert_equal(": Line 3 - section title out of sequence: expected level 1, got level 2",
              logstr.split("WARNING")[-1].chomp)
            }
          }
        })
        tc.run
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
          })
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
          })
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
