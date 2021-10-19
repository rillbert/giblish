# Generate asciidoc that represents a given pathtree as a
# verbatim block with indented, clickable entries.
class D3TreeGraph
  attr_reader :tree

  # tree: PathTree
  # === Required node data methods
  # title
  # docid
  #
  # options:
  # dir_index_base_name: String - the basename of the index file
  # residing in each directory
  def initialize(tree:, options: {dir_index_base_name: "index"})
    @tree = transform_data(tree)
    @options = options
  end

  def source
    erb_template = File.read("#{__dir__}/templates/tree.html.erb")
    ERB.new(erb_template, trim_mode: "<>").result(binding)
  end

  private

  #      1             1
  #    / | \           |-2
  #   2  5  6     ->   | |-3
  #  /\    / \         | |-4
  # 3 4   7   8        |-5
  #                    |-6
  #                      |-7
  #                      |-8
  def transform_data(tree)
    data = {}
    last_level = 0
    path = []
    # root -> left -> right
    tree.traverse_preorder do |level, node|
      d = node.leaf? ? leaf_info(node) : directory_info(node)

      if level == 0
        data = d
        path << d
      elsif level > last_level
        path[-1][:children] << d
        path << d
      elsif level == last_level
        path[-2][:children] << d
        path[-1] = d
      else
        path[level - 1][:children] << d
        path[level] = d
        path = path[0..level]
      end
      last_level = level
    end
    data
  end

  def leaf_info(node)
    conv_info = node.data
    if conv_info.converted
      name = (conv_info.docid.nil? ? "" : "#{conv_info.docid} - ") + conv_info.title
      dst_ref = conv_info.src_rel_path.sub_ext(".html")
      {
        name: name,
        dst_ref: dst_ref,
        children: []
      }
    else
      Giblog.logger.warn { "Could not get node data for #{conv_info.src_basename}" }
      {
        name: "ERR: Failed Conversion",
        dst_ref: "",
        children: []
      }
    end
  end

  def directory_info(node)
    {
      name: node.segment,
      dst_ref: "",
      children: []
    }
  end
end
