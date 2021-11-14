# $LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "giblish"
require "oga"

require "minitest/autorun"

module Giblish
  class GiblishTestBase < Minitest::Test
    def setup
      # create a logger that outputs messages to an in-memory string
      @in_mem_storage = StringIO.new
      @in_mem_logger = ::Logger.new(@in_mem_storage, formatter: Giblog::GiblogFormatter.new, level: Logger::DEBUG)

      Giblog.setup(@in_mem_logger)
      # To see all log messages in the console, uncomment this instead of the row above
      # Giblog.setup
    end

    def teardown
      return if @failures.empty?

      # puts self.instance_variables
      puts "Failed test: #{@NAME}"
      puts @in_mem_storage.string.to_s
    end
  end

  module TestUtils
    class TmpDocDir
      attr_reader :adoc_filename
      attr_reader :dir
      attr_reader :src_data_top

      # Creates a file area somewhere under /tmp.
      #
      # +preserve+ set to true if the created area should not be
      # deleted automatically (default: false)
      # +test_data_subdir+ set this to the subdir path where you
      # want all files under "../data/testdocs" to be copied to
      # in the created area. default is nil meaning no data is
      # copied. If this is set to a subdir, that dir can be
      # retrieved by accessing the @src_data_top attribute
      #
      # Use this as:
      # TmpDocDir.open do |instance|
      #   # to get the top dir
      #   top_dir = instance.dir
      #
      #   ...do your tests here...
      # end
      #
      # and be sure that the dir is deleted when the TmpDocDir goes
      # out-of-scope
      #
      def self.open(preserve: false, test_data_subdir: nil)
        instance = TmpDocDir.new(test_data_subdir)
        begin
          yield instance
        ensure
          instance.close unless preserve
        end
      end

      def close
        FileUtils.remove_entry @dir
      end

      def initialize(test_data_subdir)
        @dir = Dir.mktmpdir
        @src_data_top = nil
        unless test_data_subdir.nil?
          @src_data_top = Pathname.new(@dir).join(test_data_subdir)
          copy_test_data @src_data_top
        end
        @src_files = []
      end

      def copy_test_data(dst_top)
        # assume that the test docs reside at "../data/testdocs" relative to
        # this file
        testdir_root ||= __dir__
        src_root ||= "#{testdir_root}/../data/testdocs"

        # copy everything to the destination
        FileUtils.copy_entry(src_root, dst_top.to_s)
      end

      def create_file(relpath, doc_str = nil)
        # make dir if necessary
        dst = Pathname.new(@dir.to_s).realpath.join(relpath)
        FileUtils.mkdir_p(dst.dirname.to_s)

        # find doc source
        doc_src = doc_str || CreateAdocDocSrc.new.source

        # write the file
        File.write(dst.to_s, doc_src)
      end

      # create an asciidoc file from the given string. If user supplies
      # a subdir, the subdir will be created if not already existing and
      # the file will be created under that subdir
      def add_doc_from_str(doc_str, subdir = nil)
        dst_dir = Pathname.new(@dir.to_s).realpath
        if subdir
          dst_dir = dst_dir.join(subdir)
          FileUtils.mkdir_p(dst_dir)
        end

        # create a temp file name
        adoc_file = Tempfile.new(["gib_tst_", ".adoc"], dst_dir.to_s)

        # write doc to file and close
        adoc_file.write(doc_str)
        adoc_file.close
        @src_files << adoc_file
        adoc_file.path
      end

      # top_dir:: Pathname to the top dir of the tree where the docs shall be
      # written.
      # doc_info:: an Array with hashes where each hash describe the content or
      # metadata of one doc or a String with actual, verbatim doc content.
      # The supported hash structure looks like:
      #
      #   {hash with CreateAdocDocSrc options + a :subdir entry}
      #
      # return:: Array with the created file paths
      def create_adoc_src_on_disk(top_dir, *doc_info)
        result = []

        # p doc_info
        # p doc_info.is_a?(Hash)
        # ary = doc_info.is_a?(Hash) ? [doc_info] : Array(*doc_info)
        # p ary
        doc_info.each do |doc_config|
          doc_src = if doc_config.key?(:doc_src)
            doc_config[:doc_src]
          else
            CreateAdocDocSrc.new(doc_config).source
          end

          result << add_doc_from_str(
            doc_src,
            top_dir / doc_config.fetch(:subdir, ".")
          )
        end
        result
      end

      # usage:
      # tmp_docs.check_result_html adoc_filename do |html_tree|
      #   <process the html tree>
      # end
      def check_html_dom filename
        html_file = Pathname.new(filename.gsub(/\.adoc$/, ".html"))

        # parse the generated html and return the result to the user
        handle = File.open(html_file)
        document = Oga.parse_html(handle)
        yield document
      end

      def get_html_dom(path_tree)
        path_tree.traverse_preorder do |l, n|
          next unless n.leaf?

          # parse the generated html and return the result to the user
          handle = File.open(n.pathname.to_s)
          document = Oga.parse_html(handle)
          yield n, document
        end
      end
    end

    # Creates a string with adoc source, either a default string
    # or according to the given options.
    #
    # === Supported input options as an example
    # {
    #   title: "Doc 1",
    #   header: [":idprefix: custom", ":toc:"],
    #   paragraphs: [{
    #     title: "First paragraph",
    #     text: "Some random text"
    #   }, ... ]
    # }
    # or
    # {22
    #   doc_src: <<~DOC_SRC
    #   = My doc
    #
    #   == A paragraph
    #
    #   some text
    #   DOC_SRC
    # }
    class CreateAdocDocSrc
      attr_accessor :title, :header, :paragraphs
      attr_writer :source

      DEFAULT_OPTIONS = {
        header: [],
        paragraphs: [{title: "Paragraph 1", text: "Random text."}]
      }
      @@count = 1

      def initialize(opts = {})
        @source = opts.fetch(:doc_src, nil)
        return unless @source.nil?

        @title = opts.fetch(:title, "Document #{@@count}")
        @header = Array(opts.fetch(:header, DEFAULT_OPTIONS[:header]))
        @paragraphs = opts.fetch(:paragraphs, DEFAULT_OPTIONS[:paragraphs])
        @@count += 1
        @source = nil
      end

      def to_s
        source
      end

      def source
        @source = assemble_source if @source.nil?
        @source
      end

      private

      def assemble_source
        h_str = @header.join("\n")
        p_str = @paragraphs.collect { |p| "== #{p[:title]}\n\n#{p[:text]}\n" }.join("\n")
        <<~ADOC_SOURCE
          = #{@title}
          #{h_str}
          
          #{p_str}

        ADOC_SOURCE
      end
    end

    # copies .../data/resources/* to dst_dir/.
    def copy_test_resources(dst_dir)
      r_top = Pathname.new(__FILE__).join("../../data/resources").cleanpath
      d = Pathname.new(dst_dir)
      d.mkpath
      FileUtils.cp_r(
        r_top.to_s + "/.",
        dst_dir
      )
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
      [".", ".", "subdir"].each do |d|
        d = (repo_root / d).cleanpath.to_s
        tmp_docs.add_doc_from_str(CreateAdocDocSrc.new, d)
      end
      g.add(all: true)
      g.commit("add three files to product_1 branch")

      # checkout the main branch again
      g.checkout(g.branch("main"))

      # draw a new product branch from the main branch and
      # add some files
      g.checkout(g.branch("product_2"), {b: true})
      ["subdir", "subdir/level_2", "."].each do |d|
        d = (repo_root / d).to_s
        tmp_docs.add_doc_from_str(CreateAdocDocSrc.new, d)
      end
      g.add(all: true)
      g.commit("add three files to product_2 branch")

      # checkout the main branch
      g.checkout(g.branch("main"))

      # return repo instance
      g
    end
  end
end
