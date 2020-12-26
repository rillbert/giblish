# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/giblish/search/searchdatacache"

module Giblish
  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/AbcSize
  class TestDatacache < Minitest::Test
    include Giblish::TestUtils

    def setup
      Giblog.setup
    end

    def test_data_cache_instantiation
      file_set = {}
      TmpDocDir.open do |tmp_doc_dir|
        root_dir = tmp_doc_dir.dir
        paths = PathManager.new(root_dir, "#{root_dir}/dst")

        # ensure that the index is an empty fileinfos entry only
        s1 = SearchDataCache.new(file_set: file_set, paths: paths)
        idx = s1.heading_index
        assert_equal(idx.keys, [:fileinfos])
        assert(idx[:fileinfos].empty?)

        # add some bogus data and check that it is added
        idx[:fileinfos] << { a: 1, b: 2 }
        assert_equal(idx[:fileinfos].length, 1)

        # clear the index by instantiating a new SearchDataCache
        # object
        s2 = SearchDataCache.new(file_set: file_set, paths: paths)
        idx = s2.heading_index
        assert_equal(idx.keys, [:fileinfos])
        assert(idx[:fileinfos].empty?)
      end
    end

    def test_adding_data
      TmpDocDir.open do |tmp_doc_dir|
        root_dir = tmp_doc_dir.dir
        paths = PathManager.new(root_dir, "#{root_dir}/dst")

        # ensure that the index is an empty fileinfos entry only
        s1 = SearchDataCache.new(file_set: {}, paths: paths)
        SearchDataCache.add_file_index({ src_path: "mysrc", title: "My Title", sections: [] })
        SearchDataCache.add_file_index({ src_path: "mysrc", title: "My Title", sections: [] })

        idx = s1.heading_index
        assert_equal(idx.keys, [:fileinfos])
        assert_equal(idx[:fileinfos].length, 2)
      end
    end

    def test_serializing_index
      TmpDocDir.open do |tmp_doc_dir|
        root_dir = tmp_doc_dir.dir
        src_root = Pathname.new(root_dir) / "src"
        src_root.mkpath
        dst_root = Pathname.new(root_dir) / "dst"
        paths = PathManager.new(src_root, dst_root,nil, true)

        # ensure that the index is an empty fileinfos entry only
        s1 = SearchDataCache.new(file_set: {}, paths: paths)
        SearchDataCache.add_file_index({ src_path: src_root / "mysrc", title: "My Title", sections: [] })
        SearchDataCache.add_file_index({ src_path: src_root / "mysrc", title: "My Title", sections: [] })

        # serialize search data cache to json file
        s1.deploy_search_assets

        # ensure that relevant dirs/files exist
        assert(dst_root.directory?)
        asset_top = dst_root / "search_assets"
        assert(asset_top.directory?)
        assert((asset_top / "heading_index.json").exist?)
      end
    end
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/MethodLength
end
