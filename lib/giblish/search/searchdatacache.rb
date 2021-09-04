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
    attr_reader :id_prefix, :id_separator

    # the class-global cache of indexed section headings.
    attr_reader :heading_index

    HEADING_DB_BASENAME = "heading_db.json"

    # clean the global data cache and set up parameters given by the
    # user
    def initialize(file_tree:, id_prefix: nil, id_separator: nil)
      @heading_index = {fileinfos: []}
      @src_tree = file_tree
      @id_prefix = id_prefix
      @id_separator = id_separator
    end

    # add the indexed sections from the given file to the
    # data cache
    def add_file_index(src_path:, title:, sections:)
      @heading_index[:fileinfos] << {
        filepath: src_path.relative_path_from(@src_tree.pathname),
        title: title,
        sections: sections
      }
    end

    # called by the TreeConverter during the post_build phase
    def run(src_tree, dst_tree, converter)
      search_topdir = dst_tree.pathname / "search_assets"

      # store the JSON file
      serialize_section_index(search_topdir, search_topdir)
      
      # copy all converted adoc files
      dst_tree.traverse_preorder do |level, dst_node|
        # only copy files that were successfully converted
        next if !dst_node.leaf? || dst_node.data.nil?
        # do not copy index files, they are generated
        next if dst_node.pathname.basename.sub_ext("").to_s == "index"

        # copy all other files
        dst_path = search_topdir / dst_node.relative_path_from(dst_tree)
        FileUtils.mkdir_p(dst_path.dirname.to_s)
        FileUtils.cp(dst_node.data.src_file, dst_path.dirname)
      end
    end

    private

    # write the index to a file in dst_dir and remove the base_dir
    # part of the path for each filename
    def serialize_section_index(dst_dir, base_dir)
      dst_dir.mkpath

      heading_db_path = dst_dir.join(HEADING_DB_BASENAME)
      Giblog.logger.info { "writing json to #{heading_db_path}" }
      
      File.open(heading_db_path.to_s, "w") do |f|
        f.write(heading_index.to_json)
      end
    end
  end
end
