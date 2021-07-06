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

    # Amend the same pdf styling to all source nodes
    def setup_pdf(src_tree, pdf_style_path, pdf_fontsdir)
      src_tree.traverse_preorder do |level, n|
        next unless n.leaf? && !n.data.nil?

        class << n.data
          include PdfCustomStyle
        end

        n.data.pdf_style_path = pdf_style_path
        n.data.pdf_fontsdir = pdf_fontsdir
      end
    end

    # Amend the same linked css ref to all source nodes
    def setup_linked_css(src_tree, css_path, relative_from = nil)
      src_tree.traverse_preorder do |level, n|
        next unless n.leaf? && !n.data.nil?

        class << n.data
          include LinkedCssAttribs
        end

        n.data.css_path = relative_from.nil? ? css_path : css_path.relative_path_from(n.pathname)
      end
    end

    def test_generate_index_default_style
      TmpDocDir.open(preserve: false) do |tmp_docs|
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

        # Convert all index source nodes to html files to the same destination
        # as the converted adoc html files
        ic = TreeConverter.new(index_builder.src_tree, p / "dst")
        ic.run

        # get the node in the dst tree that points to .../dst
        dt = ic.dst_tree.node(p / "dst", from_root: true)

        # assert that there now are 2 index files under "dst"
        assert_equal(2, dt.leave_pathnames.count)
        dt.leave_pathnames.each { |p| assert_equal("index.html", p.basename.to_s) }
      end
    end

    def test_generate_index_linked_css
      TmpDocDir.open(preserve: true) do |tmp_docs|
        # create three adoc files under .../src and .../src/subdir
        ["src", "src", "src/subdir"].each { |d| puts tmp_docs.add_doc_from_str(CreateAdocDocSrc.new, d) }

        # setup the corresponding PathTree
        p = Pathname.new(tmp_docs.dir)

        fs_root = tree_from_src_dir(p / "src")

        # find the PathTree node pointing to the "src" dir
        st = fs_root.node(p / "src", from_root: true)

        assert_equal(3, st.leave_pathnames.count)

        # Convert all adoc files in the src tree to html and use a
        # 'post builder' to generate adoc source for index pages for each
        # directory.
        index_builder = IndexTreeBuilder.new(p / "dst")
        tc = TreeConverter.new(st, p / "dst", {post_builders: index_builder})
        tc.run

        # Tweak all index nodes to use the correct path when linking to
        # the css
        setup_linked_css(index_builder.src_tree, p / "web_assets")

        # Convert the index nodes to html and write them to the dst directories
        ic = TreeConverter.new(index_builder.src_tree, p / "dst")
        ic.run

        # get the node in the dst tree that points to .../dst
        dt = ic.dst_tree.node(p / "dst", from_root: true)

        # assert that there now are 2 index files under "dst"
        assert_equal(2, dt.leave_pathnames.count)
        dt.leave_pathnames.each { |p| assert_equal("index.html", p.basename.to_s) }
      end
    end

    def test_generate_index_pdf
      TmpDocDir.open(preserve: true) do |tmp_docs|
        # create three adoc files under .../src and .../src/subdir
        ["src", "src", "src/subdir"].each { |d| puts tmp_docs.add_doc_from_str(CreateAdocDocSrc.new, d) }

        # setup the corresponding PathTree
        p = Pathname.new(tmp_docs.dir)

        fs_root = tree_from_src_dir(p / "src")

        # find the PathTree node pointing to the "src" dir
        st = fs_root.node(p / "src", from_root: true)
        setup_pdf(st,
          Pathname.new(p / "resources/themes/giblish.yml"),
          nil)
        # Pathname.new(p / "resources/themes/fonts"))

        # Convert all adoc files in the src tree to html and use a
        # 'post builder' to generate adoc source for index pages for each
        # directory.
        index_builder = IndexTreeBuilder.new(p / "dst")
        tc = TreeConverter.new(st, p / "dst", {post_builders: index_builder})
        tc.run

        # Tweak all index nodes to use the correct path when linking to
        # the css
        setup_pdf(index_builder.src_tree,
          Pathname.new(p / "resources/themes/giblish.yml"),
          nil)
        # Pathname.new(p / "resources/themes/fonts"))

        # Convert the index nodes to html and write them to the dst directories
        ic = TreeConverter.new(index_builder.src_tree, p / "dst")
        ic.run

        # check what files have actually been written
        fs_result = PathTree.build_from_fs(p / "dst", prune: true) do |pt|
          !pt.directory? && pt.basename.to_s == "index.pdf"
        end

        # assert that there now are 2 index files under "dst"
        assert_equal(2, fs_result.leave_pathnames.count)
        fs_result.leave_pathnames.each { |p| assert_equal("index.pdf", p.basename.to_s) }
      end
    end
  end
end
