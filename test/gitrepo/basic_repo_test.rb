require "git"
require_relative "../test_helper"
require_relative "../../lib/giblish/treeconverter"
require_relative "../../lib/giblish/pathtree"
require_relative "../../lib/giblish/gitrepos/gititf"
require_relative "../../lib/giblish/gitrepos/history_pb"
require_relative "../../lib/giblish/gitrepos/checkoutmanager"

module Giblish
  class BasicRepoTest < Minitest::Test
    include Giblish::TestUtils

    def setup
      # setup logging
      Giblog.setup
      Giblog.logger.level = Logger::INFO
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

    def test_checkout_return_to_origin
      TmpDocDir.open(preserve: false) do |tmp_docs|
        root = Pathname.new(tmp_docs.dir)

        # setup repo with two branches
        repo = root / "tstrepo"
        setup_repo(tmp_docs, repo)

        expected_branches = %w[product_1 product_2]
        GitCheckoutManager.new(
          srcdir: repo,
          local_only: true,
          branch_regex: /.*product.*/
        ).each_checkout do |treeish,|
          assert(!expected_branches.delete(treeish).nil?)
        end
        assert_equal(0, expected_branches.count)
      end
    end

    def test_generate_html_two_branches
      TmpDocDir.open(preserve: false) do |tmp_docs|
        root = Pathname.new(tmp_docs.dir)
        dst_root = root / "dst"

        # setup repo with two branches
        repo = root / "tstrepo"
        setup_repo(tmp_docs, repo)

        # 1. Get the src dir
        # 2. Convert and add index, ...
        # 3. Redo from 1.
        tc = nil
        r = GitCheckoutManager.new(srcdir: repo, local_only: true, branch_regex: /.*product.*/)
        r.each_checkout do |name|
          Giblog.logger.info { "Working on #{name}" }

          # setup the corresponding PathTree
          fs_root = tree_from_src_dir(repo)

          st = fs_root.node(repo, from_root: true)

          assert_equal(3, st.leave_pathnames.count)

          # init a converter that use ".../src" as the top dir,
          # and generates html to ".../dst"
          branch_dst = dst_root / name.sub("/", "_")
          tc = TreeConverter.new(st, branch_dst)
          tc.run

          # assert that there now are 3 html files under "dst/<branch_name>"
          dt = tc.dst_tree.parent
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
        r = GitCheckoutManager.new(srcdir: repo, local_only: true, branch_regex: /.*product.*/)
        r.each_checkout do |name|
          Giblog.logger.info { "Working on #{name}" }

          # setup the corresponding PathTree
          fs_root = tree_from_src_dir(repo)
          st = fs_root.node(repo, from_root: true)

          # create a new top_dir for each branch/tag
          branch_dst = dst_root / name.sub("/", "_")

          # setup a tree converter with postbuilders for getting git history
          # and showing that in index
          tc = TreeConverter.new(st, branch_dst,
            {
              post_builders: [
                AddHistoryPostBuilder.new(repo), 
                SubtreeInfoBuilder.new(
                  nil,
                  nil,
                  SubtreeIndexGit,
                  "myindex"
                )
              ]
            })
          tc.run

          # assert that there now are 3 html files under "dst/<branch_name>"
          it = tc.dst_tree.match(/index.html$/).node(branch_dst, from_root: true)
          assert_equal(3, it.leave_pathnames.count)
        end
      end
    end
  end
end
