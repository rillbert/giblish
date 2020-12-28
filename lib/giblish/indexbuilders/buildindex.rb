# frozen_string_literal: true

require "pathname"
require "git"

require_relative "../pathtree"
require_relative "../gititf"
require_relative "../docinfo"
require_relative "verbatimtree"

module Giblish
  class TreeIndexBuilderItf
    def initialize(tree, path_manager, preamble, handle_docid = false)
      @paths = path_manager
      @preamble = preamble
      @manage_docid = handle_docid
      @tree = tree
    end

    def source(dep_graph_exists: false); end
  end

  # A simple index generator that shows a table with the generated documents
  class SimpleIndexBuilder < TreeIndexBuilderItf
    # set up the basic index building info
    def initialize(tree, path_manager, preamble = "")
      super(tree, path_manager, preamble)

      @src_str = ""
    end

    def source(dep_graph_exists: false)
      <<~DOC_STR
        #{title}
        #{subtitle}
        #{header}

        #{generation_info}

        #{@preamble}

        #{tree}

        #{document_details}

        #{footer}
      DOC_STR
    end

    protected

    def title
      "= Document index"
    end

    def subtitle
      "from #{@paths.src_root_abs}"
    end

    def header
      ":icons: font"
    end

    def generation_info
      "*Generated by Giblish at:* #{Time.now.strftime('%Y-%m-%d %H:%M')}"
    end

    def tree
      VerbatimTree.new(@tree).source
    end

    def add_depgraph_id
      # include link to dependency graph if it exists
      <<~DEPGRAPH_STR
        _A visual graph of document dependencies can be found
        <<./graph.adoc#,here>>
      DEPGRAPH_STR
    end

    def document_details
      details_str = String.new("== Document details\n\n")

      @tree.traverse_top_down do |_level, node|
        next unless node.leaf?

        d = node.data
        details_str << (d.converted ? document_detail(d) : document_detail_fail(d))
      end
      details_str
    end

    def footer
      ""
    end

    # return the adoc string for displaying the source file
    def display_source_file(doc_info)
      <<~SRC_FILE_TXT
        Source file::
        #{doc_info.src_file}
      SRC_FILE_TXT
    end

    private

    # return info about any conversion issues during the 
    # asciidoctor conversion
    def conversion_issues(doc_info)
      return "" if doc_info.stderr.empty?

      # extract conversion warnings from asciddoctor std err
      conv_warnings = doc_info.stderr.gsub(/^/, " * ")

      # assemble info to index page
      <<~CONV_INFO
        Conversion issues::

        #{conv_warnings}
      CONV_INFO
    end

    # Derived classes can override this with useful info
    def history_info(_doc_info)
      ""
    end

    def document_detail_fail(doc_info)
      <<~FAIL_INFO
        === #{doc_info.src_file}

        #{display_source_file(d)}

        Error detail::
        #{doc_info.stderr}

        ''''

      FAIL_INFO
    end

    # Show some details about file content
    def document_detail(doc_info)
      <<~DETAIL_SRC
        [[#{Giblish.to_valid_id(doc_info.title.encode('utf-8'))}]]
        === #{doc_info.title.encode('utf-8')}

        #{"Doc id::\n_#{doc_info.doc_id}_" unless doc_info.doc_id.nil?}

        #{"Purpose::\n#{doc_info.purpose_str}" unless doc_info.purpose_str.to_s.empty?}

        #{conversion_issues doc_info}

        #{display_source_file(doc_info)}

        #{history_info doc_info}

        ''''

      DETAIL_SRC
    end
  end

  # Builds an index of the generated documents and includes some git metadata
  # from the repository
  class GitRepoIndexBuilder < SimpleIndexBuilder
    def initialize(tree, path_manager, preamble, git_repo_root)
      super tree, path_manager, preamble

      # no repo root given...
      return unless git_repo_root

      begin
        # Make sure that we can "talk" to git if user feeds us
        # a git repo root
        @git_repo = Git.open(git_repo_root)
        @git_repo_root = git_repo_root
      rescue StandardError => e
        Giblog.logger.error { "No git repo! exception: #{e.message}" }
      end
    end

    protected

    # override basic version and use the relative path to the
    # git repo root instead
    def display_source_file(doc_info)
      # Use the path relative to the git repo root as display
      src_file = Pathname.new(doc_info.src_file)
                         .relative_path_from(@git_repo_root).to_s
      <<~SRC_FILE_TXT
        Source file::
        #{src_file}
      SRC_FILE_TXT
    end

    def subtitle
      "from #{@git_repo.current_branch}"
    end

    # Setup the table used to display file history
    HISTORY_TABLE_HEADING = <<~HISTORY_HEADER
      File history::

      [cols=\"2,3,8\",options=\"header\"]
      |===
      |Date |Author |Message
    HISTORY_HEADER

    def history_info(doc_info)
      str = String.new(HISTORY_TABLE_HEADING)

      # Generate table rows of history information
      doc_info.history.each do |h|
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
        #{footer}
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

    def footer
      ""
    end

    def generate_branch_info
      return "" if @branches.empty?

      # get the branch-unique dst-dir
      str = String.new("== Branches\n\n")

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
          |#{t.annotated? ? t.message : '-'}
          |#{t.annotated? ? t.tagger.name : '-'}
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