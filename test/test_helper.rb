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
      FileUtils.mkdir_p @dst_root

      # Instantiate a path manager with the given src and dst paths
      @paths = Giblish::PathManager.new(@src_root, @dst_root)
    end

    def teardown_log_and_paths(dry_run: true)
      if dry_run
        puts "Suppressed deletion of #{@dst_root} due to a set 'dry_run' flag"
        return
      end

      FileUtils.rm_r @dst_root

    end
  end
end