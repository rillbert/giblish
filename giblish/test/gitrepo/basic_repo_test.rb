require "git"
require "gran"
require_relative "../test_helper"
require_relative "../../lib/giblish/treeconverter"
require_relative "../../lib/giblish/gitrepos/gititf"
require_relative "../../lib/giblish/gitrepos/history_pb"
require_relative "../../lib/giblish/gitrepos/checkoutmanager"

module Giblish
  class BasicRepoTest < GiblishTestBase
    include Giblish::TestUtils

    def tree_from_src_dir(top_dir)
      src_tree = Gran::PathTree.build_from_fs(top_dir, prune: false) do |pt|
        !pt.directory? && pt.extname == ".adoc"
      end
      src_tree.traverse_preorder do |level, n|
        next unless n.leaf?

        n.data = SrcFromFile.new
      end
      src_tree
    end

    # Create test repo with two branches:
    # `main`, `product_1` and `product_2`
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
      g.add_tag("v1.0", g.branch("product_1"), {annotate: true, message: "a test tag"})

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
        opts = CmdLine::Options.new
        opts.srcdir = repo
        opts.local_only = true
        opts.branch_regex = /.*product.*/
        GitCheckoutManager.new(opts).each_checkout do |treeish|
          assert(!expected_branches.delete(treeish).nil?)
        end
        assert_equal(0, expected_branches.count)
      end
    end

    def test_git_summary_data_provider
      TmpDocDir.open(preserve: false) do |tmp_docs|
        root = Pathname.new(tmp_docs.dir)

        # setup test repo
        repo = root / "tstrepo"
        setup_repo(tmp_docs, repo)

        opts = CmdLine::Options.new
        opts.srcdir = repo
        opts.local_only = true
        opts.branch_regex = /product/
        opts.tag_regex = /v1/
        expected_treeish = %w[product_1 product_2 v1.0]
        count = matches = 0
        GitCheckoutManager.new(opts).each_checkout do |treeish|
          count += 1
          if expected_treeish.include?(treeish)
            matches += 1
          end
        end
        assert_equal(3, count)
        assert_equal(3, matches)
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
        opts = CmdLine::Options.new
        opts.srcdir = repo
        opts.local_only = true
        opts.branch_regex = /.*product.*/
        r = GitCheckoutManager.new(opts)
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
        opts = CmdLine::Options.new
        opts.srcdir = repo
        opts.local_only = true
        opts.branch_regex = /.*product.*/
        r = GitCheckoutManager.new(opts)
        r.each_checkout do |name|
          Giblog.logger.info { "Working on #{name}" }

          # setup the corresponding PathTree
          fs_root = tree_from_src_dir(repo)
          st = fs_root.node(repo, from_root: true)

          # create a new top_dir for each branch/tag
          branch_dst = dst_root / Giblish.to_fs_str(name)

          opts = CmdLine::Options.new
          opts.dstdir = dst_root
          adoc_src_provider = SubtreeIndexGit.new(
            {erb_template_path: ResourcePaths.new(opts).idx_erb_template_abs}
          )
          # setup a tree converter with postbuilders for getting git history
          # and showing that in index
          tc = TreeConverter.new(st, branch_dst,
            {
              post_builders: [
                AddHistoryPostBuilder.new(repo),
                SubtreeInfoBuilder.new(
                  nil,
                  nil,
                  adoc_src_provider,
                  "myindex"
                )
              ]
            })
          tc.run

          # assert that there now are 3 html files under "dst/<branch_name>"
          index_tree = tc.dst_tree.match(/index.html$/).node(branch_dst, from_root: true)
          assert_equal(3, index_tree.leave_pathnames.count)
        end
      end
    end
  end
end
