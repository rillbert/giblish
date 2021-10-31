require "erb"

module Giblish
  class GitSummaryDataProvider
    attr_reader :tags, :branches
    attr_accessor :index_basename

    Commit = Struct.new(:sha, :datetime, :committer, :message)
    Tag = Struct.new(:sha, :name, :date, :message, :author, :commit) do
      def id
        Giblish.to_valid_id(name)
      end
    end

    DEFAULT_GIT_SUMMARY_TEMPLATE = "/gitsummary.erb"

    def initialize(repo_name)
      @index_basename = "index"
      # all these are used by erb
      @repo_name = repo_name
      @branches = []
      @tags = []
    end

    # Cache info on one tag or branch
    #
    # repo:: a handle to a Git repo object
    # treeish:: either a Git::Tag or a Git::Branch object
    def cache_info(repo, treeish)
      if treeish.respond_to?(:tag?) && treeish.tag?
        t = cache_tag_info(repo, treeish)
        puts t
        @tags.push(t).sort_by!(&:date).reverse!
      else
        @branches << treeish.name
      end
    end

    # returns:: a string with the relative path to the index file
    #           in the given branch/tag subtree
    def index_path(treeish_name)
      Giblish.to_fs_str(treeish_name) + "/" + @index_basename + ".adoc"
    end

    def source
      erb_template = File.read(__dir__ + DEFAULT_GIT_SUMMARY_TEMPLATE)
      ERB.new(erb_template, trim_mode: "<>").result(binding)
    end

    private

    def cache_tag_info(repo, tag)
      # TODO: Fix this so it works for un-annotated tags as well.
      return nil unless tag.annotated?
      # c = repo.gcommit(tag) if tag.annotated?

      # get sha of the associated commit. (a bit convoluted...)
      c = repo.gcommit(tag.contents_array[0].split(" ")[1])
      commit = Commit.new(c.sha, c.date, c.committer.name, c.message)
      Tag.new(tag.sha, tag.name, tag.tagger.date, tag.message, tag.tagger.name, commit)
    end
  end
end