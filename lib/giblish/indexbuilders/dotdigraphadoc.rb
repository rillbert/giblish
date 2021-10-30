require_relative "../utils"

module Giblish
  # Provides a graphviz-formatted digraph of the provided node<->id ref map.
  #
  # See https://graphviz.gitlab.io/doc/conv_info/lang.html for one definition of the
  # language.
  #
  # A short example:
  #
  # [graphviz,target="docdeps",format="svg",svg-type="inline"]
  # ....
  # digraph document_deps {
  #   bgcolor="#33333310"
  #   node [shape=note,
  #         fillcolor="#ebf26680",
  #         style="filled,solid"
  #       ]
  #
  # rankdir="LR"
  #
  #
  # "D-3"[label="D-3\n Doc 3", URL="file3.html" ]
  # "D-2"[label="D-2\n Doc 2", URL="my/file2.html" ]
  # "D-1"[label="D-1\n Doc 1", URL="my/subdir/file1.html" ]
  # "D-1" -> { "D-2" "D-3"}
  # "D-2" -> { "D-1"}
  # "D-3"
  # }
  # ....
  class DotDigraphAdoc
    # info_2_ids:: A {ConversionInfo => [doc id refs]} hash.
    #
    # The following properties are expected from the ConversionInfo:
    # title:: String
    # doc_id:: String
    # dst_rel_path:: String - the relative path from a the repo top to a doc
    #                in the dst tree
    #
    # target::
    # format::
    # opts:: additional options {"opt" => "value"}. Currently supported:
    #
    # cachedir:: the directory to use for storing files produced during diagram generation.
    # svg-type:: how to embed svg images
    #
    def initialize(info_2_ids:, target: "gibgraph", format: "svg", opts: {"svg-type" => "inline"})
      @info_2_ids = info_2_ids
      @target = target
      @format = format
      @opts = opts

      @noid_docs = {}
      @next_id = 0
    end

    def source
      <<~DOC_STR
        #{graph_header}
        #{generate_labels}
        #{generate_deps}
        #{graph_footer}
      DOC_STR
    end

    private

    def graph_header
      opt_str = @opts.collect { |key, value| "#{key}=\"#{value}\"" }.join(",")
      <<~DOC_STR
        [graphviz,target="#{@target}",format="#{@format}",#{opt_str}]
        ....
        digraph document_deps {
          bgcolor="#33333310"
          labeljust=l
          node [shape=note,
                fillcolor="#ebf26680",
                style="filled,solid"
              ]

        rankdir="LR"

      DOC_STR
    end

    def graph_footer
      <<~DOC_STR
        }
        ....
      DOC_STR
    end

    def make_dot_entry(doc_dict, conv_info)
      title = conv_info&.title.nil? ? "" : Giblish.break_line(conv_info.title, 16).join("\n")

      # create the label used to display the node in the graph
      dot_entry = if conv_info.docid.nil?
        doc_id = next_fake_id
        @noid_docs[conv_info] = doc_id
        "\"#{doc_id}\"[label=\"-\n#{title}\""
      else
        doc_id = conv_info.docid
        "\"#{conv_info.docid}\"[label=\"#{conv_info.docid}\n#{title}\""
      end

      # add clickable links in the case of html output (this is not supported
      # out-of-the-box for pdf).
      rp = conv_info.dst_rel_path
      dot_entry += case rp.extname
                   when ".html"
                     ", URL=\"#{rp}\" ]"
                   else
                     " ]"
      end
      doc_dict[doc_id] = dot_entry
    end

    # create an entry in the 'dot' description for each
    # document, sort them according to descending doc id to
    # get them displayed in the opposite order in the graph
    def generate_labels
      node_dict = {}
      @info_2_ids.each_key do |conv_info|
        make_dot_entry node_dict, conv_info
      end
      # sort the nodes by reverse doc id
      node_dict = node_dict.sort.reverse.to_h

      # produce the string with all node entries
      node_dict.map do |_k, v|
        v
      end.join("\n")
    end

    def generate_deps
      dep_str = ""
      @info_2_ids.each do |conv_info, targets|
        # set either the real or the generated id as source
        src_part = if conv_info.docid.nil?
          "\"#{@noid_docs[conv_info]}\""
        else
          "\"#{conv_info.docid}\""
        end

        if targets.length.zero?
          dep_str += "#{src_part}\n"
          next
        end

        dep_str += "#{src_part} -> {" + targets.reduce("") do |acc, target|
          acc + " \"#{target}\""
        end
        # replace last comma with newline
        dep_str += "}\n"
      end
      dep_str
    end

    def next_fake_id
      @next_id += 1
      "_generated_id_#{@next_id.to_s.rjust(4, "0")}"
    end
  end
end
