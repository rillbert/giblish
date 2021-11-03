require_relative "../test_helper"
require_relative "../../lib/giblish/resourcepaths"

module Giblish
  class UseCaseTests < GiblishTestBase
    include Giblish::TestUtils

    TEST_DOCS = [
      {title: "Doc 1", header: [":idprefix: custom", ":toc:"],
       paragraphs: [
         {
           title: "First paragraph",
           text: "Some random text"
         },
         {title: "Second paragraph",
          text: "More random text"}
       ]},
      {title: "Doc 2",
       paragraphs: [{
         title: "First paragraph",
         text: "Some random text"
       },
         {title: "Second paragraph",
          text: "More random text"}],
       subdir: "subdir1"},
      {title: "Doc 3",
       paragraphs: [{
         title: "First paragraph",
         text: "Some random text"
       },
         {title: "Second paragraph",
          text: "More random text"}],
       subdir: "subdir1"}
    ]

    def create_resource_dir resource_topdir
      Dir.exist?(resource_topdir) || FileUtils.mkdir_p(resource_topdir)
      %i[dir1 dir2 images].each do |dir|
        src = "#{resource_topdir}/#{dir}"
        Dir.exist?(src) || FileUtils.mkdir(src)
      end

      # create fake custom css file
      File.write("#{resource_topdir}/dir1/custom.css", "fake custom css")

      # create fake custom yml file
      File.write("#{resource_topdir}/dir1/custom.yml",
        <<~PDF_STYLE)
          giblish:
            color:
              blue: [0, 0, 187]
              red: [184, 0, 7]
              lightgrey: [224, 224, 224]

          font:
            catalog:
              # The default font
              MyDefault:
                normal: gothic.ttf
                bold: gothicb.ttf
                italic: gothici.ttf
                bold_italic: gothicbi.ttf
              Arial:
                normal: arial.ttf
                bold: arialbd.ttf
                italic: ariali.ttf
                bold_italic: arialbi.ttf

            fallbacks:
              - Arial
          main_font_family: MyDefault

          page:
            background_color: ffffff
            layout: portrait
            margin: 20mm
            margin_inner: 2.0cm
            margin_outer: 2.0cm
            size: A4
            numbering-start-at: 1
          base:
            align: left
            font_color: $giblish_color_lightgrey
            font_family: $main_font_family
            font_size: 9
            line_height_length: 10.5
            line_height: $base_line_height_length / $base_font_size
            font_size_large: round($base_font_size * 1.25)
            font_size_small: round($base_font_size * 0.85)
            font_size_min: $base_font_size * 0.75
            font_style: normal
            border_color: $giblish_color_lightgrey
            border_radius: 4
            border_width: 0.25
          vertical_rhythm: $base_line_height_length * 2 / 3
          horizontal_rhythm: $base_line_height_length
          vertical_spacing: $vertical_rhythm
          link:
            font_color: $giblish_color_blue
          literal:
            font_color: 000000
            font_family: Courier
            font_size: 9
          title_page:
            align: left
            title:
              font_size: 30
              font_style: bold
              font_color: $giblish_color_blue
              top: 80%
            subtitle:
              font_size: 15
              font_style: bold
              font_color: 000000
            revision:
              font_size: 15
              font_style: bold
              font_color: 000000
            authors:
              font_size: 15
              font_style: bold
              font_color: 000000
          heading:
            align: left
            margin_top: $vertical_rhythm * 1.4
            margin_bottom: $vertical_rhythm * 0.7
            line_height: 1
            font_color: $giblish_color_lightgrey
            font_family: $main_font_family
            font_style: normal
            h1_font_size: 34
            h1_font_color: $giblish_color_blue
            h2_font_size: 16
            h2_font_color: $giblish_color_blue
            h3_font_size: 12
            h3_font_color: $giblish_color_blue
          authors:
            margin_top: $base_font_size * 1.25
            font_size: $base_font_size_large
            font_color: 000000
          revision:
            margin_top: $base_font_size * 1.25
          admonition:
            padding: [0, $horizontal_rhythm, 0, $horizontal_rhythm]
            border_color: $base_border_color
            column_rule_color: $base_border_color
            icon:
              warning:
                name: fa-heartbeat
                stroke_color: $giblish_color_blue
                size: 20
              caution:
                name: fa-exclamation
                stroke_color: $giblish_color_blue
                size: 20
              note:
                name: fa-info-circle
                stroke_color: $giblish_color_blue
                size: 20
              tip:
                name: fa-lightbulb-o
                stroke_color: $giblish_color_blue
                size: 20
          toc:
            font_family: $heading_font_family
            font_color: $giblish_color_blue
            #dot_leader_color: ffffff
            #dot_leader_content: ' '
            dot_leader_levels: 1
            indent: $horizontal_rhythm
            line_height: 1.4
            h1_font_style: bold
            h2_font_style: bold
        PDF_STYLE

      # create fake image
      File.write("#{resource_topdir}/images/fake_image.png", "fake png image")

      # create fake font
      File.write("#{resource_topdir}/dir1/fake_font.ttf", "fake font")
    end

    def create_adoc_src_tree tmp_docs, src_topdir
      TEST_DOCS.each do |doc_config|
        adoc_src = CreateAdocDocSrc.new(doc_config).source
        tmp_docs.add_doc_from_str(adoc_src, src_topdir / doc_config.fetch(:subdir, "."))
      end
      PathTree.build_from_fs(Pathname.new(tmp_docs.dir) / src_topdir)
    end

    def convert(src_tree, configurator)
      data_provider = DataDelegator.new(SrcFromFile.new, configurator.doc_attr)
      src_tree.traverse_preorder do |level, node|
        next unless node.leaf?

        node.data = data_provider
      end

      TreeConverter.new(src_tree, configurator.config_opts.dstdir, configurator.build_options).run
    end

    def test_generate_html_default_css
      # generate docs with asciidoctor's default css embedded in the doc

      TmpDocDir.open(preserve: false) do |tmp_docs|
        topdir = Pathname.new(tmp_docs.dir)
        src_top = topdir / "src"
        dst_top = topdir / "dst"
        create_resource_dir(topdir / "my/resources")
        tmp_docs.create_adoc_src_on_disk(src_top, *TEST_DOCS)

        opts = CmdLine.new.parse(%W[-f html #{src_top} #{dst_top}])

        src_tree = PathTree.build_from_fs(Pathname.new(src_top))
        app = Configurator.new(opts)
        convert(src_tree, app)

        # check that there are three generated docs and two index files
        doc_tree = PathTree.build_from_fs(tmp_docs.dir) { |p| p.extname == ".html" && p.basename.to_s != "index.html" }
        assert_equal(3, doc_tree.leave_pathnames.count)
        index_tree = PathTree.build_from_fs(tmp_docs.dir) { |p| p.basename.to_s == "index.html" }
        assert_equal(2, index_tree.leave_pathnames.count)

        # check that the titles are correct in the generated files
        expected_titles = TEST_DOCS.collect { |h| h[:title].dup }
        tmp_docs.get_html_dom(doc_tree) do |node, dom|
          next if !node.leaf? || /index.html$/ =~ node.pathname.to_s

          nof_headers = 0
          dom.xpath("//h1").each do |title|
            nof_headers += 1
            assert(expected_titles.reject! { |t| t == title.text })
          end
          assert_equal(1, nof_headers)
        end
        assert(expected_titles.empty?)

        # assert that the css link is only the google font api
        # used by asciidoctor by default
        html_result = PathTree.build_from_fs(topdir / "dst")
        expected_hrefs = [
          "https://fonts.googleapis.com/css?family=Open+Sans:300,300italic,400,400italic,"\
              "600,600italic%7CNoto+Serif:400,400italic,700,700italic%7CDroid+Sans+Mono:400,700",
          "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.min.css"
        ]
        tmp_docs.get_html_dom(html_result) do |node, document|
          document.xpath("html/head/link").each do |csslink|
            assert_equal "stylesheet", csslink.get("rel")
            assert(expected_hrefs.include?(csslink.get("href")))
          end
        end
      end
    end

    # test that the css link is a relative link to the css file in the
    # local file system when user does not give web path
    #
    # giblish -r <resource_dir> --s style src dst
    # shall yield:
    # dst
    # |- file.html
    # |- subdir
    # |    |- file.html (href ../web_assets/css/giblish.css)
    # |...
    # |- web_assets
    # |    |- css
    #          |- giblish.css
    def test_generate_html_use_resource_dir
      TmpDocDir.open(preserve: false) do |tmp_docs|
        topdir = Pathname.new(tmp_docs.dir)
        copy_test_resources(topdir / "resources")
        src_top = create_adoc_src_tree(tmp_docs, topdir / "src")

        opts = CmdLine.new.parse(%W[-f html -r #{topdir / "resources"} -s giblish #{topdir} #{topdir / "dst"}])
        app = Configurator.new(opts)
        convert(src_top, app)

        # check that the files are there
        r = PathTree.build_from_fs(topdir / "dst", prune: false)
        docs = r.filter { |l, n| !(/web_assets/ =~ n.pathname.to_s) }
        assert_equal(5, docs.leave_pathnames.count)
        assert_equal(2, r.match(/index.html$/).leave_pathnames.count)

        # assert that the css link is only the google font api
        # used by asciidoctor by default
        expected_hrefs = [
          "https://fonts.googleapis.com/css?family=Open+Sans:300,300italic,400,400italic,"\
              "600,600italic%7CNoto+Serif:400,400italic,700,700italic%7CDroid+Sans+Mono:400,700",
          "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.min.css",
          "placeholder for relative path"
        ]
        tmp_docs.get_html_dom(docs) do |node, document|
          nof_links = 0
          document.xpath("html/head/link").each do |csslink|
            # get the expected relative path from the top dst dir
            rp = (topdir / "dst/web_assets/web/giblish.css").relative_path_from(node.pathname.dirname)

            expected_hrefs[2] = rp.to_s
            assert_equal "stylesheet", csslink.get("rel")
            assert(expected_hrefs.include?(csslink.get("href")))
            nof_links += 1
          end
          assert(nof_links > 0)
        end
      end
    end

    def test_generate_html_use_fix_css_path
      TmpDocDir.open(preserve: false) do |tmp_docs|
        topdir = Pathname.new(tmp_docs.dir)
        # copy_test_resources(topdir / "resources")
        src_top = create_adoc_src_tree(tmp_docs, topdir / "src")

        opts = CmdLine.new.parse(%W[-f html --server-css-path my/style/giblish.css #{topdir} #{topdir / "dst"}])
        app = Configurator.new(opts)
        convert(src_top, app)

        # check that the files are there
        r = PathTree.build_from_fs(topdir / "dst", prune: true)
        docs = r.filter { |l, n| !(/web_assets/ =~ n.pathname.to_s) }
        assert_equal(5, docs.leave_pathnames.count)
        assert_equal(2, r.match(/index.html$/).leave_pathnames.count)
      end
    end

    def test_generate_pdf_default_style
      TmpDocDir.open(preserve: false) do |tmp_docs|
        topdir = Pathname.new(tmp_docs.dir)
        create_resource_dir(topdir / "my/resources")
        src_top = create_adoc_src_tree(tmp_docs, topdir / "src")

        opts = CmdLine.new.parse(%W[-f pdf #{topdir} #{topdir / "dst"}])
        app = Configurator.new(opts)
        convert(src_top, app)

        # check that the files are there
        r = PathTree.build_from_fs(topdir / "dst", prune: true)
        assert_equal(5, r.leave_pathnames.count)
        assert_equal(2, r.match(/index.pdf$/).leave_pathnames.count)
      end
    end

    def test_generate_pdf_custom_yml
      TmpDocDir.open(preserve: false) do |tmp_docs|
        topdir = Pathname.new(tmp_docs.dir)
        copy_test_resources(topdir / "my/resources")
        src_top = create_adoc_src_tree(tmp_docs, topdir / "src")

        opts = CmdLine.new.parse(%W[-f pdf -r #{topdir / "my/resources"} -s giblish #{topdir} #{topdir / "dst"}])
        app = Configurator.new(opts)
        convert(src_top, app)

        # check that the files are there
        r = PathTree.build_from_fs(topdir / "dst", prune: true)
        assert_equal(5, r.leave_pathnames.count)
        assert_equal(2, r.match(/index.pdf$/).leave_pathnames.count)
      end
    end

    def test_html_from_gitrepo
      TmpDocDir.open(preserve: false) do |tmp_docs|
        topdir = Pathname.new(tmp_docs.dir)

        # setup repo with two branches
        repo_top = topdir / "tstrepo"
        setup_repo(tmp_docs, repo_top)

        src_top = repo_top
        dst_top = topdir / "dst"

        create_resource_dir(topdir / "my/resources")

        # repo_tree = PathTree.build_from_fs(repo_top, prune:  true)
        # puts repo_tree.to_s
        EntryPoint.run(%W[-f html -c -g .* #{src_top} #{dst_top}])

        dsttree = PathTree.build_from_fs(dst_top, prune: true)
        assert(dsttree.leave_pathnames.count > 0)

        expected_branches = %w[product_1 product_2 index.html]
        dsttree.children.each do |c|
          assert(expected_branches.any? { |b| b == c.segment })
        end
      end
    end

    def test_graph_is_created_depending_on_graphviz
      TmpDocDir.open(test_data_subdir: "src_top") do |tmp_docs|
        dst_top = "#{tmp_docs.dir}/dst_top"
        src_top = Pathname.new(tmp_docs.dir).join("src_top/wellformed/docidtest")
        src_tree = PathTree.build_from_fs(Pathname.new(src_top))

        opts = CmdLine.new.parse(%W[--resolve-docid #{src_top} #{dst_top}])
        app = Configurator.new(opts)
        convert(src_tree, app)

        if Giblish.which("dot")
          assert(File.exist?("#{dst_top}/gibgraph.html"))
        else
          assert(!File.exist?("#{dst_top}/gibgraph.html"))
        end

        assert(File.exist?("#{dst_top}/index.html"))
        assert(!File.exist?("#{dst_top}/gibgraph.svg"))
      end
    end
  end
end
