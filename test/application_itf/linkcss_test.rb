require_relative "../test_helper"
require_relative "../../lib/giblish"

class LinkCSSTest < Minitest::Test
  include Giblish::TestUtils

  @@test_doc = <<~EOF
    = Test css linking
    :numbered:
    
    == My First Section

    Some dummy text....
    
    == My Second Section

    Some more dummy text...
    
  EOF

  def create_resource_dir resource_topdir
    Dir.exist?(resource_topdir) || FileUtils.mkdir_p(resource_topdir)
    %i[css fonts images].each do |dir|
      src = "#{resource_topdir}/#{dir}"
      Dir.exist?(src) || FileUtils.mkdir(src)
    end

    # create fake custom css file
    File.write("#{resource_topdir}/css/custom.css", "fake custom css")
    File.write("#{resource_topdir}/css/giblish.css", "fake custom css")
    # create fake image
    File.write("#{resource_topdir}/images/fake_image.png", "fake png image")
    # create fake font
    File.write("#{resource_topdir}/fonts/fake_font.ttf", "fake font")
  end


  def setup
    # setup logging
    Giblog.setup
  end

  # generate a doc without embedded style info but pointing
  # to the stylesheet given by the -w flag.
  # TODO: Decide how to treat a set -w and unset -s!!!
  #  giblish -w '/my/webserver/topdir' src dst
  def test_webroot_only
    TmpDocDir.open do |tmp_docs|
      # create a doc under the .../subdir folder
      adoc_filename = tmp_docs.add_doc_from_str(@@test_doc, "subdir")
      args = ["--log-level", "info",
        "-w", "/my/webserver/topdir",
        tmp_docs.dir,
        tmp_docs.dir]
      Giblish.application.run args

      # assert that the css link is only the google font api
      # used by asciidoctor by default
      expected_hrefs = [
        "/my/webserver/topdir"
      ]
      count = 0
      tmp_docs.check_html_dom adoc_filename do |html_dom|
        html_dom.xpath("html/head/link").each do |csslink|
          count += 1
          assert_equal "stylesheet", csslink.get("rel")
          expected_hrefs.reject! { |l| l == csslink.get("href") }
        end
      end
      assert_equal(1, count)
      assert_equal(0, expected_hrefs.count)
    end
  end

  # test that the css link is a relative link to the css file in the
  # local file system when user does not give web path
  #
  # giblish -r <resource_dir> src dst
  # shall yield:
  # dst
  # |- subdir
  # |    |- file.html (href ../web_assets/css/giblish.css)
  # |- web_assets
  # |    |- css
  #          |- giblish.css
  def test_custom_styling_without_webroot
    TmpDocDir.open do |tmp_docs|
      # create a resource dir
      r_dir = "#{tmp_docs.dir}/resources"
      create_resource_dir r_dir

      # act on the input data
      adoc_filename = tmp_docs.add_doc_from_str(@@test_doc, "src/subdir")
      args = ["--log-level", "info",
        "-r", r_dir,
        "-s", "giblish",
        "#{tmp_docs.dir}/src",
        "#{tmp_docs.dir}/dst"]
      Giblish.application.run args

      # assert that the css link is relative to the specific
      # css file (../web_assets/css/giblish.css)
      tmp_docs.check_html_dom adoc_filename.gsub("src/", "dst/") do |html_tree|
        css_links = html_tree.xpath("html/head/link")
        assert_equal 1, css_links.count

        css_links.each do |csslink|
          assert_equal "stylesheet", csslink.get("rel")
          assert_equal "../web_assets/css/giblish.css",
            csslink.get("href")
        end
      end
    end
  end

  # test that the css link is a relative link to the css file
  # TODO: Decide how to treat this combo of flags
  # giblish -w /my/web/root -r <resource_dir> -s custom src dst
  def test_custom_styling_with_webroot
    TmpDocDir.open do |tmp_docs|
      # create a resource dir
      r_dir = "#{tmp_docs.dir}/resources"
      create_resource_dir r_dir

      web_root = Pathname("/my/web/root")
      # create a doc in the 'subdir' folder.
      adoc_filename = tmp_docs.add_doc_from_str(@@test_doc, "subdir")
      args = ["--log-level", "info",
        "-w", web_root.to_s,
        "-r", r_dir,
        "-s", "custom",
        tmp_docs.dir,
        tmp_docs.dir]
      Giblish.application.run args

      # the link shall work when the doc is published on a web server
      # under the given web path
      expected_csslink = Pathname.new("/my/web/root/web_assets/css/custom.css")

      tmp_docs.check_html_dom adoc_filename do |html_tree|
        css_links = html_tree.xpath("html/head/link")
        assert_equal 1, css_links.count

        css_links.each do |csslink|
          assert_equal "stylesheet", csslink.get("rel")
          assert_equal expected_csslink.to_s, csslink.get("href")
        end
      end
    end
  end
end
