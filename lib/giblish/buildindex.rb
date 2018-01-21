#!/usr/bin/env ruby
#

require "pathname"
require "git"
require_relative "cmdline"
require_relative "pathtree"
require_relative "gititf"

# Container class for bundling together the data we cache for
# each asciidoc file we come across
class DocInfo
  # Cache git info
  class DocHistory
    attr_accessor :date
    attr_accessor :author
    attr_accessor :message
  end

  attr_accessor :converted
  attr_accessor :title
  attr_accessor :doc_id
  attr_accessor :purpose_str
  attr_accessor :status
  attr_accessor :history
  attr_accessor :error_msg
  attr_accessor :stderr
  # these two members can have encoding issues when
  # running in a mixed Windows/Linux setting.
  # that is why the explicit utf-8 read methods are
  # provided.
  attr_accessor :relPath
  attr_accessor :srcFile

  def relPath_utf8
    return nil if @relPath.nil?
    @relPath.to_s.encode("utf-8")
  end

  def srcFile_utf8
    return nil if @srcFile.nil?
    @srcFile.to_s.encode("utf-8")
  end

  def initialize
    @history = []
  end

  def to_s
    "DocInfo: title: #{@title} srcFile: #{srcFile_utf8}"
  end
end

# Base class with common functionality for all index builders
class BasicIndexBuilder
  # set up the basic index building info
  def initialize(path_manager, handle_docid = false)
    @paths = path_manager
    @nof_missing_titles = 0
    @added_docs = []
    @src_str = ""
    @manage_docid = handle_docid
  end

  # creates a DocInfo instance, fills it with basic info and
  # returns the filled in instance so that derived implementations can
  # add more data
  def add_doc(adoc, adoc_stderr)
    Giblog.logger.debug { "Adding adoc: #{adoc} Asciidoctor stderr: #{adoc_stderr}" }
    Giblog.logger.debug {"Doc attributes: #{adoc.attributes}"}

    info = DocInfo.new
    info.converted = true
    info.stderr = adoc_stderr

    # Get the purpose info if it exists
    info.purpose_str = get_purpose_info adoc

    # Get the relative path beneath the root dir to the doc
    d_attr = adoc.attributes
    info.relPath = Pathname.new(
      "#{d_attr['outdir']}/#{d_attr['docname']}#{d_attr['docfilesuffix']}"
    ).relative_path_from(
      @paths.dst_root_abs
    )

    # Get the doc id if it exists
    info.doc_id = adoc.attributes["docid"]

    # Get the source file path
    info.srcFile = adoc.attributes["docfile"]

    # If a docid exists, set titel to docid - title if we care about
    # doc ids.
    info.title = if !info.doc_id.nil? && @manage_docid
                   "#{info.doc_id} - #{adoc.doctitle}"
                 else
                   adoc.doctitle
                 end

    # Cache the created DocInfo
    @added_docs << info
    info
  end

  def add_doc_fail(filepath, exception)
    info = DocInfo.new

    # the only info we have is the source file name
    info.converted = false
    info.srcFile = filepath
    info.error_msg = exception.message

    # Cache the DocInfo
    @added_docs << info
    info
  end

  def index_source
    <<~DOC_STR
      #{generate_header}
      #{generate_tree}
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

  def generate_footer
    ""
  end

  private

  def get_purpose_info(adoc)
    # Get the 'Purpose' section if it exists
    purpose_str = ""
    adoc.blocks.each do |section|
      next unless section.is_a?(Asciidoctor::Section) &&
                  (section.level == 1) &&
                  (section.name =~ /^Purpose$/)
      purpose_str = "Purpose::\n\n"

      # filter out 'odd' text, such as lists etc...
      section.blocks.each do |bb|
        next unless bb.is_a?(Asciidoctor::Block)
        purpose_str << "#{bb.source}\n+\n"
      end
    end
    purpose_str
  end

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
  # Returns [ clickableTitleStr, clickableDetailsStr ]
  def format_title_and_ref(doc_info)
    unless doc_info.title
      @nof_missing_titles += 1
      doc_info.title = "NO TITLE FOUND (#{@nof_missing_titles}) !"
    end
    return "<<#{doc_info.relPath_utf8}#,#{doc_info.title}>>".encode("utf-8"),
    "<<#{Giblish.to_valid_id(doc_info.title)},details>>\n".encode("utf-8")
  end

  # Generate an adoc string that will display as
  # DocTitle         (warn)  details
  # Where the DocTitle and details are links to the doc itself and a section
  # identified with the doc's title respectively.
  def tree_entry_converted(prefix_str, doc_info)
    # Get the elements of the entry
    doc_title, doc_details = format_title_and_ref doc_info
    warning_label = doc_info.stderr.empty? ? "" : "(warn)"

    # Calculate padding to get (warn) and details aligned between entries
    padding = 80
    [doc_info.title, prefix_str, warning_label].each { |p| padding -= p.length }
    padding = 0 unless padding.positive?
    "#{prefix_str} #{doc_title}#{' ' * padding}#{warning_label} #{doc_details}"
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

  def generate_tree
    # build up tree of paths
    root = PathTree.new
    @added_docs.each do |d|
#      root.add_path(d.relPath.to_s, d)
      root.add_path(d.relPath_utf8, d)
    end

    # output tree intro
    tree_string = <<~DOC_HEADER
      == Document Overview

      _Click on the title to open the document or on `details` to see more
      info about the document. A `(warn)` label indicates that there were
      warnings while converting the document._

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
    <<~DETAIL_SRC
      [[#{Giblish.to_valid_id(d.title.encode("utf-8"))}]]
      === #{d.title.encode("utf-8")}

      #{d.purpose_str}

      #{generate_conversion_info d}

      Source file::
      #{d.srcFile_utf8}

      #{generate_history_info d}

      ''''

    DETAIL_SRC
  end

  def generate_details
    root = PathTree.new
    @added_docs.each do |d|
      root.add_path(d.relPath.to_s, d)
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
  def initialize(path_manager, manage_docid = false)
    super path_manager, manage_docid
  end

  def add_doc(adoc, adoc_stderr)
    super(adoc, adoc_stderr)
  end
end

# Builds an index of the generated documents and includes some git metadata
# repository
class GitRepoIndexBuilder < BasicIndexBuilder
  def initialize(path_manager, manage_docid, git_repo_root)
    super path_manager, manage_docid

    # initialize state variables
    @git_repo_root = git_repo_root

    # no repo root given...
    return unless @git_repo_root

    begin
      # Make sure that we can "talk" to git if user feeds us
      # a git repo root
      @git_repo = Git.open(@git_repo_root)
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
  def initialize(repo)
    @branches = []
    @tags = []
    @repo_url = repo.remote.url
  end

  def add_branch(b)
    @branches << b
  end

  def add_tag(t)
    @tags << t
  end

  def index_source
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

    TAG_INFO

    @tags.each do |t|
      dirname = t.name.tr "/", "_"
      str << " * link:#{dirname}/index.html[#{t.name}]\n"
    end
    str
  end
end
