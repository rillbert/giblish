# Generate asciidoc that represents a given pathtree as a
# verbatim block with indented, clickable entries.
class D3Tree
  # options:
  # dir_index_base_name: String - the basename of the index file
  # residing in each directory
  def initialize(tree, options)
    @tree = tree
    @nof_missing_titles = 0
    @options = options.dup
  end

  def source
    # output tree intro
    graph = File.read("#{__dir__}/templates/tree.html.erb")
    return <<~DOC_SRC
    = A Graph test

    Some text 
    ++++
    #{graph}
    ++++

    Some more text
    DOC_SRC
  end
end
