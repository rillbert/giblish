require "pathname"
require "git"

require_relative "pathtree"
require_relative "gititf"
require_relative "docinfo"

module Giblish

  # Base class with common functionality for all index builders
  class BasicIndexBuilder
    # set up the basic index building info
    def initialize(processed_docs, converter, path_manager, handle_docid = false)
      @paths = path_manager
      @nof_missing_titles = 0
      @processed_docs = processed_docs
      @converter = converter
      @src_str = ""
      @manage_docid = handle_docid
    end

    def source(dep_graph_exists = false, make_searchable = false)
      <<~DOC_STR
        #{generate_title_and_header}
        #{generate_date_info}
        #{add_search_box if make_searchable}
        #{generate_tree(dep_graph_exists)}
        #{generate_details}
        #{generate_footer}
      DOC_STR
    end

    protected
    def generate_title_and_header
      <<~DOC_HEADER
        = Document index
        from #{@paths.src_root_abs}
        :icons: font

      DOC_HEADER
    end

    # return the adoc string for displaying the source file
    def display_source_file(doc_info)
      <<~SRC_FILE_TXT
        Source file::
        #{doc_info.src_file}

      SRC_FILE_TXT
    end

    def generate_date_info
      t = Time.now
      <<~DOC_HEADER
        *Generated by Giblish at:* #{t.strftime('%Y-%m-%d %H:%M')}
      DOC_HEADER
    end

    def add_search_box
      # TODO: Fix the hard-coded path
      cgi_path = "/cgi-bin/giblish-search.cgi"
      css = @converter.converter_options[:attributes]["stylesheet"]

      # button with magnifying glass icon (not working when deployed)
      # <button id="search" type="submit"><i class="fa fa-search"></i></button>
      <<~SEARCH_INFO
      ++++
        <form class="example" action="#{cgi_path}" style="margin:20px 0px 20px 0px;max-width:380px">
            Search all documents: 
            <input id="searchphrase" type="text" placeholder="Search.." name="searchphrase"/>
            <button id="search" type="submit">Search</button>
            <br>

            <input id="ignorecase" type="checkbox" value="true" name="ignorecase" checked/>
            <label for="ignorecase">Ignore Case</label>
            &nbsp;&nbsp;
            <input id="useregexp" type="checkbox" value="true" name="regexp"/>
            <label for="useregexp">Use Regexp</label>

            <input type="hidden" name="topdir" value="#{@paths.dst_root_abs.to_s}"</input>
            <input type="hidden" name="reltop" value="#{@paths.reldir_from_web_root(@paths.dst_root_abs)}"</input>
            <input type="hidden" name="css" value="#{css}"</input>
        </form>
      ++++

      SEARCH_INFO
    end
    def get_docid_statistics
      largest = ""
      clash = []
      @processed_docs.each do |d|
        # get the lexically largest doc id
        largest = d.doc_id if !d.doc_id.nil? && d.doc_id > largest

        # collect all ids in an array to find duplicates later on
        clash << d.doc_id unless d.doc_id.nil?
      end
      # find the duplicate doc ids (if any)
      duplicates = clash.select { |id| clash.count(id) > 1 }.uniq.sort

      return largest,duplicates
    end

    def generate_doc_id_info(dep_graph_exists)
      largest,duplicates = get_docid_statistics
      docid_info_str = if ! @manage_docid
                         ""
                       else
                         "The 'largest' document id found when resolving :docid: tags in all documents is *#{largest}*."
                       end

      docid_warn_str = if duplicates.length.zero?
                         ""
                       else
                         "WARNING: The following document ids are used for more than one document. " +
                             "_#{duplicates.map {|id| id.to_s}.join(",") }_"
                       end

      # include link to dependency graph if it exists
      dep_graph_str = if dep_graph_exists
                        "_(a visual graph of document dependencies can be found " \
                      "<<./graph.adoc#,here>>)_"
                      else
                        ""
                      end

      if @manage_docid
        <<~DOC_ID_INFO
        *Document id numbers:* #{docid_info_str} #{dep_graph_str}
  
        #{docid_warn_str}

        DOC_ID_INFO
      else
        ""
      end
    end

    def generate_tree(dep_graph_exists)
      # output tree intro
      tree_string = <<~DOC_HEADER
        #{generate_doc_id_info dep_graph_exists}

        [subs=\"normal\"]
        ----
      DOC_HEADER

      # build up tree of paths
      root = PathTree.new
      @processed_docs.each do |d|
        root.add_path(d.rel_path.to_s, d)
      end

      # sort the tree
      root.sort_children

      # generate each tree entry string
      root.traverse_top_down do |level, node|
        tree_string << tree_entry_string(level, node)
      end

      # generate the tree footer
      tree_string << "\n----\n"
    end

    def generate_footer
      ""
    end

    private

    def generate_conversion_info(d)
      return "" if d.stderr.empty?
      # extract conversion warnings from asciddoctor std err
      conv_warnings = d.stderr.gsub(/^/, " * ")

      # assemble info to index page
      <<~CONV_INFO
        Conversion issues::

        #{conv_warnings}
      CONV_INFO
    end

    # Private: Return adoc elements for displaying a clickable title
    # and a 'details' ref that points to a section that uses the title as an id.
    #
    # Returns [ title, clickableTitleStr, clickableDetailsStr ]
    def format_title_and_ref(doc_info)
      unless doc_info.title
        @nof_missing_titles += 1
        doc_info.title = "NO TITLE FOUND (#{@nof_missing_titles}) !"
      end

      # Manipulate the doc title if we have a doc id
      title = if !doc_info.doc_id.nil? && @manage_docid
                "#{doc_info.doc_id} - #{doc_info.title}"
              else
                doc_info.title
              end

      [title, "<<#{doc_info.rel_path}#,#{title}>>",
       "<<#{Giblish.to_valid_id(doc_info.title)},details>>\n"]
    end

    # Generate an adoc string that will display as
    # DocTitle         (conv issues)  details
    # Where the DocTitle and details are links to the doc itself and a section
    # identified with the doc's title respectively.
    def tree_entry_converted(prefix_str, doc_info)
      # Get the elements of the entry
      doc_title, doc_link, doc_details = format_title_and_ref doc_info
      warning_label = doc_info.stderr.empty? ? "" : "(conv issues)"

      # Calculate padding to get (conv issues) and details aligned between entries
      padding = 70
      [doc_title, prefix_str, warning_label].each {|p| padding -= p.length}
      padding = 0 unless padding.positive?
      "#{prefix_str} #{doc_link}#{' ' * padding}#{warning_label} #{doc_details}"
    end

    def tree_entry_string(level, node)
      # indent 2 * level
      prefix_str = "  " * (level + 1)

      # return only name for directories
      return "#{prefix_str} #{node.name}\n" unless node.leaf?

      # return links to content and details for files
      # node.data is a DocInfo instance
      d = node.data
      if d.converted
        tree_entry_converted prefix_str, d
      else
        # no converted file exists, show what we know
        "#{prefix_str} FAIL: #{d.src_file}      <<#{d.src_file},details>>\n"
      end
    end

    # Derived classes can override this with useful info
    def generate_history_info(_d)
      ""
    end

    def generate_detail_fail(d)
      <<~FAIL_INFO
        === #{d.src_file}

        #{display_source_file(d)}

        Error detail::
        #{d.stderr}

        ''''

      FAIL_INFO
    end

    def generate_detail(d)
      # Generate detail info
      purpose_str = if d.purpose_str.nil?
                      ""
                    else
                      "Purpose::\n#{d.purpose_str}"
                    end

      doc_id_str = if !d.doc_id.nil? && @manage_docid
                     "Doc id::\n_#{d.doc_id}_"
                   else
                     ""
                   end

      <<~DETAIL_SRC
        [[#{Giblish.to_valid_id(d.title.encode("utf-8"))}]]
        === #{d.title.encode("utf-8")}

        #{doc_id_str}

        #{purpose_str}

        #{generate_conversion_info d}

        #{display_source_file(d)}

        #{generate_history_info d}

        ''''

      DETAIL_SRC
    end

    def generate_details
      root = PathTree.new
      @processed_docs.each do |d|
        root.add_path(d.rel_path.to_s, d)
      end

      details_str = "== Document details\n\n"

      root.traverse_top_down do |_level, node|
        details_str << if node.leaf?
                         d = node.data
                         if d.converted
                           generate_detail(d)
                         else
                           generate_detail_fail(d)
                         end
                       else
                         ""
                       end
      end
      details_str
    end
  end

  # A simple index generator that shows a table with the generated documents
  class SimpleIndexBuilder < BasicIndexBuilder
    def initialize(processed_docs, converter, path_manager, manage_docid = false)
      super processed_docs, converter, path_manager, manage_docid
    end
  end

  # Builds an index of the generated documents and includes some git metadata
  # from the repository
  class GitRepoIndexBuilder < BasicIndexBuilder
    def initialize(processed_docs, converter, path_manager, manage_docid, git_repo_root)
      super processed_docs, converter, path_manager, manage_docid

      # no repo root given...
      return unless git_repo_root

      begin
        # Make sure that we can "talk" to git if user feeds us
        # a git repo root
        @git_repo = Git.open(git_repo_root)
        @git_repo_root = git_repo_root
      rescue Exception => e
        Giblog.logger.error {"No git repo! exception: #{e.message}"}
      end
    end

    protected
    # override basic version and use the relative path to the
    # git repo root instead
    def display_source_file(doc_info)
      # Use the path relative to the git repo root as display
      src_file = Pathname.
          new(doc_info.src_file).
          relative_path_from(@git_repo_root).to_s
      <<~SRC_FILE_TXT
        Source file::
        #{src_file}

      SRC_FILE_TXT
    end


    def generate_title_and_header
      t = Time.now
      <<~DOC_HEADER
        = Document index
        #{@git_repo.current_branch}

        :icons:

      DOC_HEADER
    end

    def generate_history_info(d)
      str = <<~HISTORY_HEADER
        File history::

        [cols=\"2,3,8\",options=\"header\"]
        |===
        |Date |Author |Message
      HISTORY_HEADER

      # Generate table rows of history information
      d.history.each do |h|
        str << <<~HISTORY_ROW
          |#{h.date.strftime('%Y-%m-%d')}
          |#{h.author}
          |#{h.message}

        HISTORY_ROW
      end
      str << "|===\n\n"
    end
  end

  # Builds an index page with a summary of what branches have
  # been generated
  class GitSummaryIndexBuilder
    def initialize(repo, branches, tags)
      @branches = branches
      @tags = tags
      @git_repo = repo
      @repo_url = repo.remote.url
    end

    def source
      <<~ADOC_SRC
        #{generate_header}
        #{generate_branch_info}
        #{generate_tag_info}
        #{generate_footer}
      ADOC_SRC
    end

    private

    def generate_header
      t = Time.now
      <<~DOC_HEADER
        = Document repository
        From #{@repo_url}

        Generated by Giblish at::
        #{t.strftime('%Y-%m-%d %H:%M')}

      DOC_HEADER
    end

    def generate_footer
      ""
    end

    def generate_branch_info
      return "" if @branches.empty?

      # get the branch-unique dst-dir
      str = <<~BRANCH_INFO
        == Branches

      BRANCH_INFO

      @branches.each do |b|
        dirname = b.name.tr "/", "_"
        str << " * link:#{dirname}/index.html[#{b.name}]\n"
      end
      str
    end

    def generate_tag_info
      return "" if @tags.empty?

      # get the branch-unique dst-dir
      str = <<~TAG_INFO
        == Tags
        
        |===
        |Tag |Tag comment |Creator |Tagged commit 

      TAG_INFO

      str << @tags.collect do |t|
        dirname = t.name.tr "/", "_"
        c = @git_repo.gcommit(t.sha)

        <<~A_ROW
          |link:#{dirname}/index.html[#{t.name}]
          |#{t.annotated? ? t.message : "-"}
          |#{t.annotated? ? t.tagger.name : "-"}
          |#{t.sha[0, 8]}... committed at #{c.author.date}
        A_ROW
      end.join("\n")

      str << "|===\n"

      # @tags.each do |t|
      #   dirname = t.name.tr "/", "_"
      #   str << " * link:#{dirname}/index.html[#{t.name}]"
      #   if t.annotated?
      #     str << "created at #{t.tagger.date} by #{t.tagger.name} with message: #{t.message}"
      #   end
      # end
      str
    end
  end
end