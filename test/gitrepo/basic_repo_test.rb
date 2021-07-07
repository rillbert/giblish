require "git"
require_relative "../test_helper"
require_relative "../../lib/giblish/treeconverter"
require_relative "../../lib/giblish/pathtree"
require_relative "../../lib/giblish/gititf"
require_relative "../../lib/giblish/gitrepos/checkoutmanager"

module Giblish
  class BasicRepoTest < Minitest::Test
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

    def setup_repo(tmp_docs, repo_root)
      # init new repo
      g = Git.init(repo_root.to_s) # , {log: Giblog.logger})
      g.config("user.name", "Test Robot")
      g.config("user.email", "robot@giblishtest.com")

      # create the main branch
      g.checkout(g.branch("main"), {b: true})
      g.commit("dummy commit", {allow_empty: true})

      # add some files to the "product_1" branch
      g.checkout(g.branch("product_1"), {b: true})
      ["src", "src", "src/subdir"].each do |d|
        d = (repo_root / d).to_s
        tmp_docs.add_doc_from_str(CreateAdocDocSrc.new, d)
      end
      g.add(all: true)
      g.commit("add three files to product_1 branch")

      # checkout the main branch again
      g.checkout(g.branch("main"))

      # draw a new product branch from the main branch and
      # add some files
      g.checkout(g.branch("product_2"), {b: true})
      ["src", "src", "src/subdir"].each do |d|
        d = (repo_root / d).to_s
        tmp_docs.add_doc_from_str(CreateAdocDocSrc.new, d)
      end
      g.add(all: true)
      g.commit("add three files to product_2 branch")

      # checkout the main branch
      g.checkout(g.branch("main"))
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

    def test_setup_repo
      setup_repo
    end

    def test_generate_html_two_branches
      TmpDocDir.open(preserve: true) do |tmp_docs|
        root = Pathname.new(tmp_docs.dir)
        dst_root = root / "dst"

        # setup repo with two branches
        repo = root / "tstrepo"
        setup_repo(tmp_docs, repo)

        # 1. Get the src dir
        # 2. Convert and add index, ...
        # 3. Redo from 1.
        tc = nil
        r = GitCheckoutManager.new(git_repo_root: repo, local_only: true, branch_regex: /.*product.*/)
        r.each_checkout do |name|
          Giblog.logger.info { "Working on #{name}" }

          # setup the corresponding PathTree
          fs_root = tree_from_src_dir(repo)

          st = fs_root.node(repo, from_root: true)

          assert_equal(3, st.leave_pathnames.count)

          # init a converter that use ".../src" as the top dir,
          # and generates html to ".../dst"
          branch_dst = dst_root / name.sub("/", "_")
          tc = tc.nil? ? TreeConverter.new(st, branch_dst) : tc.init_src_dst(st, branch_dst)
          tc.run

          # assert that there now are 3 html files under "dst/<branch_name>"
          dt = tc.dst_tree.node(dst_root, from_root: true)
          assert_equal(3, dt.leave_pathnames.count)
          assert_equal(
            st.leave_pathnames.collect { |p| branch_dst.basename / p.sub_ext(".html").relative_path_from(st.pathname) },
            dt.leave_pathnames.collect { |p| p.relative_path_from(dt.pathname) }
          )
        end
      end
    end

    def test_generate_html_two_branches_with_index
      TmpDocDir.open(preserve: true) do |tmp_docs|
        root = Pathname.new(tmp_docs.dir)
        dst_root = root / "dst"

        # setup repo with two branches
        repo = root / "tstrepo"
        setup_repo(tmp_docs, repo)

        # 1. Get the src dir
        # 2. Convert and add index, ...
        # 3. Redo from 1.
        tc = nil
        index_builder = nil
        r = GitCheckoutManager.new(git_repo_root: repo, local_only: true, branch_regex: /.*product.*/)
        r.each_checkout do |name|
          Giblog.logger.info { "Working on #{name}" }

          # setup the corresponding PathTree
          fs_root = tree_from_src_dir(repo)
          st = fs_root.node(repo, from_root: true)

          # create a new top_dir for each branch/tag
          branch_dst = dst_root / name.sub("/", "_")

          # remove all src nodes and reset to a fresh builder
          index_builder = index_builder.nil? ? IndexTreeBuilder.new(branch_dst) : index_builder.reset(branch_dst)

          # setup a tree converter, using the index_builder
          tc = tc.nil? ? TreeConverter.new(st, branch_dst,
            {
              post_builders: index_builder,
              conversion_cb: {
                success: ->(src, dst, dst_rel_path, doc, logstr) do
                  tc.on_success(src, dst, dst_rel_path, doc, logstr)

                  # Get the commit history of the doc
                  # (use a homegrown git log to get 'follow' flag)
                  gi = Giblish::GitItf.new(repo)
                  p = src.pathname.relative_path_from(repo)
                  gi.file_log(p.to_s).each do |i|
                    dst.data.history << DocInfo::DocHistory.new(i["date"], i["author"], i["message"])
                  end
                end,
                failure: ->(src, dst, dst_rel_path, ex, logstr) { tc.on_failure(src, dst, dst_rel_path, ex, logstr) }
              }
            }) : tc.init_src_dst(st, branch_dst)
          tc.run

          # Tweak all index nodes to use the correct path when linking to
          # the css
          # setup_linked_css(index_builder.src_tree, dst_root / "web_assets")

          # Convert the index nodes to html and write them to the dst directories
          ic = TreeConverter.new(index_builder.src_tree, branch_dst)
          ic.run

          # assert that there now are 3 html files under "dst/<branch_name>"
          dt = tc.dst_tree.node(dst_root, from_root: true)
          assert_equal(3, dt.leave_pathnames.count)
          assert_equal(
            st.leave_pathnames.collect { |p| branch_dst.basename / p.sub_ext(".html").relative_path_from(st.pathname) },
            dt.leave_pathnames.collect { |p| p.relative_path_from(dt.pathname) }
          )
        end
      end
    end
  end
end
