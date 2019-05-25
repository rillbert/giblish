$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'giblish'

require 'minitest/autorun'

module Giblish
  module TestUtils
    # a path manager to query for src and dst paths
    attr :paths
    attr_accessor :testdir_root
    attr_accessor :src_root
    attr_accessor :dst_root
    attr_reader :dir_created

    # defaults to
    # testdir_root = <working_dir>
    # src_root = <working_dir>/../data/testdocs
    # dst_root = <working_dir>/../testoutput
    def setup_log_and_paths
      # setup logging
      Giblog.setup

      # setup paths from previous user input or default
      @testdir_root ||= File.expand_path(File.dirname(__FILE__))
      @src_root ||= "#{@testdir_root}/../data/testdocs"
      @dst_root ||= "#{@testdir_root}/../testoutput"

      # create the dir if needed and keep track of if we created it
      @dir_created = false
      unless Dir.exists? @dst_root
        FileUtils.mkdir_p @dst_root
        @dir_created = true
      end

      # Instantiate a path manager with the given src and dst paths
      @paths = Giblish::PathManager.new(@src_root, @dst_root)
    end

    def teardown_log_and_paths(dry_run: true)
      if dry_run
        Giblog.logger.info "Suppress deletion of #{@dst_root} due to a set 'dry_run' flag"
        return
      end

      unless @dir_created
        Giblog.logger.info "Suppress deletion of #{@dst_root}. It existed before the tests started."
        return
      end

      FileUtils.rm_r @dst_root
    end

    class TmpDocDir
      attr_reader :adoc_filename
      attr_reader :dir

      # enable a user of this class to do things like:
      # TmpDocDir.open do |doc_dir|
      # ...
      # end
      # and be sure that the dir is deleted afterwards
      def self.open(preserve = false)
        instance = TmpDocDir.new
        begin
          yield instance
        ensure
          instance.close unless preserve
        end
      end

      def close
        FileUtils.remove_entry @dir
      end

      def initialize
        @dir = Dir.mktmpdir
        @src_files = []
      end

      # usage:
      # tmp_docs.check_result_html adoc_filename do |html_tree|
      #   <process the html tree>
      # end
      def check_result_html filename
        html_file = Pathname.new(filename.gsub(/\.adoc$/,'.html'))

        # parse the generated html and return the result to the user
        handle = File.open(html_file)
        document = Oga.parse_html(handle)
        yield document
      end

      def add_doc_from_str(doc_str)
        # create a temp file name
        adoc_file = Tempfile.new(['gib_tst_','.adoc'],@dir)

        # write doc to file and close
        adoc_file.puts doc_str
        adoc_file.close
        @src_files << adoc_file
        adoc_file.path
      end
    end

  end
end