require "git"
require "date"
require_relative "../utils"
require_relative "../version"
require_relative "gititf"
require_relative "gitsummaryprovider"

module Giblish
  # acquires a handle to an existing git repo and provide the user
  # with a iteration method 'each_checkout' where each matching branch and/or tag is
  # checked out and presented to the user code.
  class GitCheckoutManager
    attr_reader :branches, :tags, :summary_provider, :git_repo, :repo_root

    # srcdir:: Pathname to the top dir of the local git repo to work with
    # local_only:: if true, do not try to access any remote branches or merge with any
    # upstream changes
    # branch_regex:: the regex for the branches to include during iteration (default: none)
    # tag_regex:: the regex for the tags to include during iteration (default: none)
    def initialize(srcdir:, local_only: false, branch_regex: nil, tag_regex: nil, erb_template: nil)
      @repo_root = GitItf.find_gitrepo_root(srcdir)
      raise ArgumentError("The path: #{srcdir} is not within a git repo!") if @repo_root.nil?

      @local_only = local_only
      @git_repo = init_git_repo(@repo_root, local_only)
      @branches = select_user_branches(branch_regex, local_only)
      @tags = select_user_tags(tag_regex)
      @erb_template = erb_template
      @summary_provider = GitSummaryDataProvider.new(@repo_root.basename)
      # TODO: Do not hardcode this!
      @abort_on_error = true
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
      checkouts = (@branches + @tags)
      if checkouts.empty?
        Giblog.logger.info { "No matching branches or tags found." }
        return
      end

      checkouts.each do |treeish|
        sync_treeish(treeish)
        # cache branch/tag info for downstream content generation
        @summary_provider.cache_info(@git_repo, treeish)

        yield(treeish.name)
      rescue => e
        Giblog.logger.error { e.message }
        raise e if @abort_on_error
      end

      if @git_repo.current_branch != current_branch
        Giblog.logger.info { "Checking out '#{current_branch}'" }
        @git_repo.checkout current_branch
      end
    end

    private

    def sync_treeish(treeish)
      Giblog.logger.info { "Checking out '#{treeish.name}'" }
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
