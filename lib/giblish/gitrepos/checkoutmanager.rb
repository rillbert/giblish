require "git"
require "date"
require "erb"
require_relative "../utils"
require_relative "../version"
require_relative "gititf"

module Giblish
  class GitSummaryDataProvider
    attr_reader :tags, :branches

    Commit = Struct.new(:sha, :datetime, :committer, :message)
    Tag = Struct.new(:sha, :name, :date, :message, :author, :commit) do
      def id
        Giblish.to_valid_id(name)
      end
    end

    def self.source(data_provider)
      template = File.read("gitsummary.erb", encoding: "UTF-8")
      summary = ERB.new(template, trim_mode: "<>")
      summary.result(data_provider.get_binding)
    end

    def initialize(repo_name)
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
        @tags.push(t).sort_by!(&:date).reverse!
        # @tags << t unless t.nil?
      else
        @branches << treeish.name
      end
    end

    # supply an ERB binding
    def get_binding
      binding
    end

    # returns:: a string with the relative path to the index file
    #           in the given branch/tag subtree
    def index_path(treeish_name)
      Giblish.to_fs_str(treeish_name) + "/index.adoc"
    end

    private

    def cache_tag_info(repo, tag)
      return nil unless tag.annotated?

      # get sha of the associated commit. (a bit convoluted...)
      c = repo.gcommit(tag.contents_array[0].split(" ")[1])
      commit = Commit.new(c.sha, c.date, c.committer.name, c.message)
      Tag.new(tag.sha, tag.name, tag.tagger.date, tag.message, tag.tagger.name, commit)
    end
  end

  # acquires a handle to an existing git repo and provide the user
  # with a iteration method 'each_checkout' where each matching branch and/or tag is
  # checked out and presented to the user code.
  class GitCheckoutManager
    attr_reader :branches, :tags, :git_data

    # srcdir:: Pathname to the top dir of the local git repo to work with
    # local_only:: if true, do not try to access any remote branches or merge with any
    # upstream changes
    # branch_regex:: the regex for the branches to include during iteration (default: none)
    # tag_regex:: the regex for the tags to include during iteration (default: none)
    def initialize(srcdir:, local_only: false, branch_regex: nil, tag_regex: nil)
      repo_root = GitItf.find_gitrepo_root(srcdir)
      raise ArgumentError("The path: #{srcdir} is not within a git repo!") if repo_root.nil?

      @local_only = local_only
      @git_repo = init_git_repo(repo_root, local_only)
      @branches = select_user_branches(branch_regex, local_only)
      @tags = select_user_tags(tag_regex)
      @git_data = GitSummaryDataProvider.new(repo_root.basename)
    end

    # present each git checkout matching the init criteria to the user's code.
    #
    # === Example
    #
    # gcm = GitCheckoutManager.new(my_repo_root, true, /release/, /final/)
    # gcm.each_checkout do |name|
    # ... do things with the currently checked out working tree ...
    # end
    def each_checkout
      current_branch = @git_repo.current_branch
      begin
        (@branches + @tags).each do |treeish|
          sync_treeish(treeish)
          # cache branch/tag info for downstream content generation
          @git_data.cache_info(@git_repo, treeish)

          yield(treeish.name)
        end
      ensure
        Giblog.logger.info { "Checking out #{current_branch}" }
        @git_repo.checkout current_branch
      end
    end

    private

    def sync_treeish(treeish)
      Giblog.logger.info { "Checking out #{treeish.name}" }
      @git_repo.checkout treeish.name

      # merge branches with their upstream at origin unless
      # 'only local'
      unless (treeish.respond_to?(:tag?) && treeish.tag?) || @local_only
        # this is a branch, make sure it is up-to-date
        Giblog.logger.info { "Merging with origin/#{treeish.name}" }
        @git_repo.merge "origin/#{treeish.name}"
      end
    end

    def init_git_repo(git_repo_root, local_only)
      # Sanity check git repo root
      git_repo_root || raise(ArgumentError("No git repo root dir given"))

      msg = "Could not find a git repo at #{git_repo_root} !"
      begin
        # Connect to the git repo
        git_repo = Git.open(git_repo_root)
        # fetch all remote refs if ok with user
        msg = "Could not fetch from origin (do you need '--local-only'?)!"
        git_repo.fetch unless local_only
      rescue => e
        raise "#{msg}\n\n#{e.message}"
      end
      git_repo
    end

    # Get the branches/tags the user wants to parse
    def select_user_branches(regexp, local_only)
      return [] unless regexp

      user_checkouts = local_only ? @git_repo.branches.local : @git_repo.branches.remote
      user_checkouts.select! do |b|
        # match branches but remove eventual HEAD -> ... entry
        regexp.match b.name unless /^HEAD/.match?(b.name)
      end
      Giblog.logger.debug { "selected git branches: #{user_checkouts.collect { |b| b.name }.join(", ")}" }
      user_checkouts
    end

    def select_user_tags(regexp)
      return [] unless regexp

      @git_repo.tags.select do |t|
        regexp.match t.name
      end
    end
  end
end
