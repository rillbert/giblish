module Giblish
  # Search
  #
  # 1. Collect user input and set up a search data cache
  # 2. Hook into the asciidoctor engine and index headings
  #    when invoked for a source file. Store the indes in the data cache
  # 3. Copy data cache and source docs to the correct destination
  #    directory.
  #
  #
  # top_dir
  # |- web_assets
  # |- branch_1_top_dir
  # |     |- index.html
  # |     |- file1.html
  # |     |- dir_1
  # |     |   |- file2.html
  # |- search_assets
  # |     |- branch_1
  # |           |- heading_index.json
  # |           |- file1.adoc
  # |           |- dir_1
  # |           |   |- file2.adoc
  # |           |- ...
  # |     |- branch_2
  # |           | ...
  # |- branch_2_top_dir
  # | ...
  class SearchDataCache
    # the class-global cache of indexed section headings.
    @heading_index = { fileinfos: [] }
    @id_prefix = nil
    @id_separator = nil

    class << self
      attr_reader :heading_index
      attr_accessor :id_separator, :id_prefix

      def clear
        @heading_index = { fileinfos: [] }
      end

      # add the indexed sections from the given file to the
      # data cache
      def add_file_index(src_path:, title:, sections:)
        @heading_index[:fileinfos] << {
          filepath: src_path,
          title: title,
          sections: sections
        }
      end
    end

    # Convenience method that let users access the global data cache
    # via a SearchDataCache object
    def heading_index
      SearchDataCache.heading_index
    end

    # clean the global data cache and set up parameters given by the
    # user
    def initialize(file_set:, paths:, id_prefix: nil, id_separator: nil)
      @adoc_files = file_set
      @paths = paths
      SearchDataCache.id_prefix = id_prefix
      SearchDataCache.id_separator = id_separator

      # make sure we start from a clean slate
      SearchDataCache.clear
    end

    # Create needed assets for the search to work. This method
    # 1. Serializes the 'database' with the indexed headings to a JSON
    #    file in the proper location in the destination
    # 2. Copies all source files that are included in the search space to
    #    a mirrored hierarchy within the destination tree.
    def deploy_search_assets(asset_top_dir = nil)
      # get the proper dir for the search assets
      assets_dir = @paths.search_assets_abs

      # store the JSON file
      serialize_section_index(assets_dir, asset_top_dir || @paths.src_root_abs)

      # traverse the src file tree and copy all processed adoc files
      # to the search_assets dir
      @adoc_files.each do |p|
        dst_dir = assets_dir.join(@paths.reldir_from_src_root(p))
        FileUtils.mkdir_p(dst_dir)
        FileUtils.cp(p.to_s, dst_dir)
      end
    end

    private

    # write the index to a file in dst_dir and remove the base_dir
    # part of the path for each filename
    def serialize_section_index(dst_dir, base_dir)
      # make sure its a Pathname
      dst_dir = Pathname.new(dst_dir)

      remove_base_dir(base_dir)

      Giblog.logger.info { "writing json to #{dst_dir.join('heading_index.json')}" }
      File.open(dst_dir.join("heading_index.json").to_s, "w") do |f|
        f.write(heading_index.to_json)
      end
    end

    # remove the base_dir part of the file path
    def remove_base_dir(base_dir)
      return unless base_dir

      heading_index[:fileinfos].each do |file_info|
        file_info[:filepath] = Pathname.new(file_info[:filepath])
                                       .relative_path_from(base_dir)
      end
    end
  end
end
