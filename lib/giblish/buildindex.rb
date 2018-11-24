#!/usr/bin/env ruby
#

require "pathname"
require "git"
require_relative "cmdline"
require_relative "pathtree"
require_relative "gititf"
require_relative "docinfo"

# Base class with common functionality for all index builders
class BasicIndexBuilder
  # set up the basic index building info
  def initialize(processed_docs, path_manager, handle_docid = false)
    @paths = path_manager
    @nof_missing_titles = 0
    @processed_docs = processed_docs
    @src_str = ""
    @manage_docid = handle_docid
  end

  def source(dep_graph_exists = false)
    <<~DOC_STR
      #{generate_header}
      #{generate_tree(dep_graph_exists)}
      #{generate_details}
      #{generate_footer}
    DOC_STR
  end

  protected

  def generate_header
    t = Time.now
    <<~DOC_HEADER
      = Document index
      from #{@paths.src_root_abs}

      Generated by Giblish at::

      #{t.strftime('%Y-%m-%d %H:%M')}

    DOC_HEADER
  end

  def generate_tree(dep_graph_exists)
    # build up tree of paths
    root = PathTree.new
    @processed_docs.each do |d|
      root.add_path(d.rel_path.to_s, d)
    end

    # include link to dependency graph if it exists
    dep_graph_str = if dep_graph_exists
                      "_(a visual graph of document dependencies can be found " \
                      "<<./graph.adoc#,here>>)_"
                    else
                      ""
                    end
    # output tree intro
    tree_string = <<~DOC_HEADER
      == Document Overview

      _Click on the title to open the document or on `details` to see more
      info about the document. A `(warn)` label indicates that there were
      warnings while converting the document._

      #{dep_graph_str}

      [subs=\"normal\"]
      ----
    DOC_HEADER

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
    conv_warnings = d.stderr.gsub("asciidoctor:", "\n * asciidoctor:")
    Giblog.logger.warn { "Conversion warnings: #{conv_warnings}" }

    # assemble info to index page
    <<~CONV_INFO
      Conversion info::

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

    [title, "<<#{doc_info.rel_path}#,#{title}>>".encode("utf-8"),
     "<<#{Giblish.to_valid_id(title)},details>>\n".encode("utf-8")]
  end

  # Generate an adoc string that will display as
  # DocTitle         (warn)  details
  # Where the DocTitle and details are links to the doc itself and a section
  # identified with the doc's title respectively.
  def tree_entry_converted(prefix_str, doc_info)
    # Get the elements of the entry
    doc_title, doc_link, doc_details = format_title_and_ref doc_info
    warning_label = doc_info.stderr.empty? ? "" : "(warn)"

    # Calculate padding to get (warn) and details aligned between entries
    padding = 70
    [doc_title, prefix_str, warning_label].each { |p| padding -= p.length }
    padding = 0 unless padding.positive?
    "#{prefix_str} #{doc_link}#{' ' * padding}#{warning_label} #{doc_details}"
  end

  def tree_entry_string(level, node)
    # indent 2 * level
    prefix_str = "  " * (level + 1)

    # return only name for directories
    return "#{prefix_str} #{node.name}\n" unless node.leaf?

    # return links to content and details for files
    d = node.data
    if d.converted
      tree_entry_converted prefix_str, d
    else
      # no converted file exists, show what we know
      "#{prefix_str} FAIL: #{d.srcFile_utf8}      <<#{d.srcFile_utf8},details>>\n"
    end
  end

  # Derived classes can override this with useful info
  def generate_history_info(_d)
    ""
  end

  def generate_detail_fail(d)
    <<~FAIL_INFO
      === #{d.srcFile_utf8}

      Source file::

      #{d.srcFile_utf8}

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
    <<~DETAIL_SRC
      [[#{Giblish.to_valid_id(d.title.encode("utf-8"))}]]
      === #{d.title.encode("utf-8")}

      #{purpose_str}

      #{generate_conversion_info d}

      Source file::
      #{d.srcFile_utf8}

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
  def initialize(processed_docs, path_manager, manage_docid = false)
    super processed_docs, path_manager, manage_docid
  end
end

# Builds an index of the generated documents and includes some git metadata
# repository
class GitRepoIndexBuilder < BasicIndexBuilder
  def initialize(processed_docs, path_manager, manage_docid, git_repo_root)
    super processed_docs, path_manager, manage_docid

    # Redefine the src_file to mean the relative path to the git repo root
    @processed_docs.each do |info|
      info.src_file = Pathname.new(
        info.src_file
      ).relative_path_from(git_repo_root).to_s
    end

    # no repo root given...
    return unless git_repo_root

    begin
      # Make sure that we can "talk" to git if user feeds us
      # a git repo root
      @git_repo = Git.open(git_repo_root)
    rescue Exception => e
      Giblog.logger.error { "No git repo! exception: #{e.message}" }
    end
  end

  def add_doc(adoc, adoc_stderr)
    info = super(adoc, adoc_stderr)

    # Redefine the srcFile to mean the relative path to the git repo root
    info.srcFile = Pathname.new(info.srcFile).relative_path_from(@git_repo_root).to_s

    # Get the commit history of the doc
    # (use a homegrown git log to get 'follow' flag)
    gi = Giblish::GitItf.new(@git_repo_root)
    gi.file_log(info.srcFile_utf8).each do |i|
      h = DocInfo::DocHistory.new
      h.date = i["date"]
      h.message = i["message"]
      h.author = i["author"]
      info.history << h
    end
  end

  protected

  def generate_header
    t = Time.now
    <<~DOC_HEADER
      = Document index
      #{@git_repo.current_branch}

      Generated by Giblish at::
      #{t.strftime('%Y-%m-%d %H:%M')}

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
        |#{t.sha[0,8]}... committed at #{c.author.date}
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
