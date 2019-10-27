$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'giblish'
require 'oga'

require 'minitest/autorun'

module Giblish
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
        testdir_root ||= File.expand_path(File.dirname(__FILE__))
        src_root ||= "#{testdir_root}/../data/testdocs"

        # copy everything to the destination
        FileUtils.copy_entry(src_root,dst_top.to_s)
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

      # create an asciidoc file from the given string. If user supplies
      # a subdir, the subdir will be created if not already existing and
      # the file will be created under that subdir
      def add_doc_from_str(doc_str,subdir=nil)
        dst_dir = Pathname.new(@dir.to_s).realpath
        if subdir
          dst_dir = dst_dir.join(subdir)
          FileUtils.mkdir_p(dst_dir)
        end

        # create a temp file name
        adoc_file = Tempfile.new(['gib_tst_','.adoc'],dst_dir.to_s)

        # write doc to file and close
        adoc_file.puts doc_str
        adoc_file.close
        @src_files << adoc_file
        adoc_file.path
      end
    end

  end
end