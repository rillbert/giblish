require_relative "../test_helper"
require_relative "../../lib/giblish/resource_management"

module Giblish
  # tests the basic functionality of the Application class
  class HtmlLocalResourceTest < Minitest::Test
    include Giblish::TestUtils

    def setup
      # setup logging
      Giblog.setup
    end

    def create_resource_dir resource_topdir
      Dir.exist?(resource_topdir) || FileUtils.mkdir_p(resource_topdir)
      %i[dir1 dir2 images].each do |dir|
        src = "#{resource_topdir}/#{dir}"
        Dir.exist?(src) || FileUtils.mkdir(src)
      end

      # create fake custom css file
      css_fake = File.open("#{resource_topdir}/dir1/custom.css", "w")
      css_fake.puts "fake custom css"
      css_fake.close

      # create fake custom yml file
      css_fake = File.open("#{resource_topdir}/dir1/custom.yml", "w")
      css_fake.puts <<~PDF_STYLE
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
      css_fake.close

      # create fake image
      image_fake = File.open("#{resource_topdir}/images/fake_image.png", "w")
      image_fake.puts "fake png image"
      image_fake.close

      # create fake font
      font_fake = File.open("#{resource_topdir}/dir1/fake_font.ttf", "w")
      font_fake.puts "fake font"
      font_fake.close
    end

    def create_adoc_src_tree tmp_docs, src_topdir
      tmp_docs.add_doc_from_str(CreateAdocDocSrc.new({header: ":idprefix: custom"}).source, src_topdir)
      tmp_docs.add_doc_from_str(CreateAdocDocSrc.new.source, src_topdir / "subdir1")
      tmp_docs.add_doc_from_str(CreateAdocDocSrc.new.source, src_topdir / "subdir1")
      p_top = Pathname.new(tmp_docs.dir) / src_topdir
      src_tree = PathTree.build_from_fs(p_top)
      src_tree.node(p_top, from_root: true)
    end

    def test_generate_html_default_css
      TmpDocDir.open(preserve: true) do |tmp_docs|
        topdir = Pathname.new(tmp_docs.dir)
        create_resource_dir(topdir / "my/resources")
        src_top = create_adoc_src_tree(tmp_docs, topdir / "src")

        opts = CmdLine.new.parse(%W[-f html #{topdir} #{topdir / "dst"}])
        app = Configurator.new(opts, src_top)
        app.tree_converter.run

        r = PathTree.build_from_fs(topdir, prune: true)
        puts r
      end
    end

    def test_generate_html_use_resource_dir
      TmpDocDir.open(preserve: false) do |tmp_docs|
        topdir = Pathname.new(tmp_docs.dir)
        copy_test_resources(topdir / "resources")
        src_top = create_adoc_src_tree(tmp_docs, topdir / "src")

        opts = CmdLine.new.parse(%W[-f html -r #{topdir / "resources"} -s giblish #{topdir} #{topdir / "dst"}])
        app = Configurator.new(opts, src_top)
        app.tree_converter.run

        # check that the files are there
        r = PathTree.build_from_fs(topdir / "dst", prune: true)
        docs = r.filter { |l, n| !(/web_assets/ =~ n.pathname.to_s) }
        assert_equal(5, docs.leave_pathnames.count)
        assert_equal(2, r.match(/index.html$/).leave_pathnames.count)
      end
    end

    def test_generate_html_use_fix_css_path
      TmpDocDir.open(preserve: true) do |tmp_docs|
        topdir = Pathname.new(tmp_docs.dir)
        # copy_test_resources(topdir / "resources")
        src_top = create_adoc_src_tree(tmp_docs, topdir / "src")

        opts = CmdLine.new.parse(%W[-f html -w my/style/giblish.css #{topdir} #{topdir / "dst"}])
        app = Configurator.new(opts, src_top)
        app.tree_converter.run

        # check that the files are there
        r = PathTree.build_from_fs(topdir / "dst", prune: true)
        docs = r.filter { |l, n| !(/web_assets/ =~ n.pathname.to_s) }
        assert_equal(5, docs.leave_pathnames.count)
        assert_equal(2, r.match(/index.html$/).leave_pathnames.count)
      end
    end

    def test_generate_pdf_default_style
      TmpDocDir.open(preserve: true) do |tmp_docs|
        topdir = Pathname.new(tmp_docs.dir)
        create_resource_dir(topdir / "my/resources")
        src_top = create_adoc_src_tree(tmp_docs, topdir / "src")

        opts = CmdLine.new.parse(%W[-f pdf #{topdir} #{topdir / "dst"}])
        app = Configurator.new(opts, src_top)
        app.tree_converter.run

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
        app = Configurator.new(opts, src_top)
        app.tree_converter.run

        # check that the files are there
        r = PathTree.build_from_fs(topdir / "dst", prune: true)
        assert_equal(5, r.leave_pathnames.count)
        assert_equal(2, r.match(/index.pdf$/).leave_pathnames.count)
      end
    end

    def test_generate_search_data_assets
      TmpDocDir.open(preserve: true) do |tmp_docs|
        topdir = Pathname.new(tmp_docs.dir)
        src_top = create_adoc_src_tree(tmp_docs, topdir / "src")

        # opts = CmdLine.new.parse(%W[-f html -m #{topdir} #{topdir / "dst"}])
        opts = CmdLine.new.parse(%W[-f html -a idprefix=idefix -m #{topdir} #{topdir / "dst"}])
        app = Configurator.new(opts, src_top)
        app.tree_converter.run

        # r = PathTree.build_from_fs(topdir, prune: true)
        # puts r
      end
    end
  end
end
