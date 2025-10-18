# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "../gran/lib/gran"

require "minitest/autorun"
require "minitest/hooks/test"

module Gran
  module TestUtils
    #
    # Configures a logger object used by the gem
    # during testing.
    #
    # @return [None]
    #
    # AIDEV-NOTE: uses in-memory logging to avoid filesystem artifacts during tests
    def self.config_test_logger
      # Configure a logger object to use for the gem

      # Use some color in the output
      Logging.color_scheme("bright",
        levels: {
          info: :green,
          warn: :yellow,
          error: :red,
          fatal: [:white, :on_red]
        },
        date: :blue,
        logger: :cyan,
        message: :magenta)

      # Create a logger object
      logger = Logging.logger["GranTest"]

      # Create in-memory storage for log messages
      in_mem_storage = StringIO.new

      # Set up the logger to log to stdout and to in-memory storage
      logger.add_appenders(
        Logging.appenders.stdout(
          layout: Logging.layouts.pattern(
            pattern: '[%d] %-5l %c: %m\n',
            color_scheme: "bright"
          )
        ),
        Logging.appenders.io("test_memory", in_mem_storage,
          layout: Logging.layouts.pattern(
            pattern: '[%d] %-5l %c: %m\n'
          ))
      )
      # Set the log level for the logger
      logger.level = :debug

      # Assign the logger to the gem
      Gran.logger = logger
    end

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

    # copies .../data/resources/* to dst_dir/.
    # def copy_test_resources(dst_dir)
    #   r_top = Pathname.new(__FILE__).join("../../data/resources").cleanpath
    #   d = Pathname.new(dst_dir)
    #   d.mkpath
    #   FileUtils.cp_r(
    #     r_top.to_s + "/.",
    #     dst_dir
    #   )
    # end

    # def setup_repo(tmp_docs, repo_root)
    #   # init new repo
    #   g = Git.init(repo_root.to_s) # , {log: Giblog.logger})
    #   g.config("user.name", "Test Robot")
    #   g.config("user.email", "robot@giblishtest.com")

    #   # create the main branch
    #   g.checkout(g.branch("main"), {b: true})
    #   g.commit("dummy commit", {allow_empty: true})

    #   # add some files to the "product_1" branch
    #   g.checkout(g.branch("product_1"), {b: true})
    #   [".", ".", "subdir"].each do |d|
    #     d = (repo_root / d).cleanpath.to_s
    #     tmp_docs.add_doc_from_str(CreateAdocDocSrc.new, d)
    #   end
    #   g.add(all: true)
    #   g.commit("add three files to product_1 branch")

    #   # checkout the main branch again
    #   g.checkout(g.branch("main"))

    #   # draw a new product branch from the main branch and
    #   # add some files
    #   g.checkout(g.branch("product_2"), {b: true})
    #   ["subdir", "subdir/level_2", "."].each do |d|
    #     d = (repo_root / d).to_s
    #     tmp_docs.add_doc_from_str(CreateAdocDocSrc.new, d)
    #   end
    #   g.add(all: true)
    #   g.commit("add three files to product_2 branch")

    #   # checkout the main branch
    #   g.checkout(g.branch("main"))

    #   # return repo instance
    #   g
    # end
  end

  class GranTestBase < Minitest::Test
    include Minitest::Hooks
    include Loggable
    include TestUtils

    def before_all
      TestUtils.config_test_logger
    end

    def after_all
      # currently not used
    end
  end
end

require "logging"
