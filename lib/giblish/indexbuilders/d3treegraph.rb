# Generate asciidoc that represents a given pathtree as a
# verbatim block with indented, clickable entries.
class D3TreeGraph
  # tree: PathTree
  # === Required node data methods
  # title
  # docid
  #
  # options:
  # dir_index_base_name: String - the basename of the index file
  # residing in each directory
  def initialize(tree:, options: {dir_index_base_name: "index"}) #target: "d3graph", format: "svg", opts: {})
    @tree = transform_data(tree)
    @options = options
  end

  def source
    erb_template = File.read("#{__dir__}/templates/tree.html.erb")
    ERB.new(erb_template, trim_mode: "<>").result(binding)
    # <<~DOC_SRC
    #   = A Graph test

    #   Some text 
    #   ++++
    #   #{graph}
    #   ++++

    #   Some more text
    # DOC_SRC
  end

  private

  def transform_data(tree)
    data = {}
    last_level = 0
    path = []
    # root -> left -> right
    tree.traverse_preorder do |level, node|
      conv_info = node.data
      # Display docid and title as name
      d = {
        name: (conv_info.docid.nil? ? "" : "#{conv_info.docid} - ") + conv_info.title,
        children: []
      }

      if level == 0 
        data = d
        path << d
      elsif level > last_level
        path[-1][:children] << d
        path << d        
      elsif level == last_level
        path[-1][:children] << d
      else
        path[level-1][:children] << d
        path[level] = d
        path = path[0..level]
      end
      last_level = level
    end
    data
  end
end
