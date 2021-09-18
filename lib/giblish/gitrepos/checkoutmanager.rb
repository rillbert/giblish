require "git"

module Giblish
  # acquires a handle to an existing git repo and provide the user
  # with a iteration method 'each_checkout' where each matching branch and/or tag is
  # checked out and presented to the user code.
  class GitCheckoutManager
    attr_reader :branches_and_tags

    # git_repo_root:: Pathname to the top dir of the local git repo to work with
    # local_only:: if true, do not try to access any remote branches or merge with any
    # upstream changes
    # branch_regex:: the regex for the branches to include during iteration (default: none)
    # tag_regex:: the regex for the tags to include during iteration (default: none)
    def initialize(srcdir: , local_only: false, branch_regex: nil, tag_regex: nil)
      repo_root = find_gitrepo_root(srcdir)
      raise ArgumentError("The path: #{srcdir} is not within a git repo!") if repo_root.nil?

      @local_only = local_only
      @git_repo = init_git_repo(repo_root, local_only)
      @branches_and_tags = select_user_branches(branch_regex, local_only) + select_user_tags(tag_regex)
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
        @branches_and_tags.each do |b|
          sync_treeish(b)

          yield(b.name)
        end
      ensure
        Giblog.logger.info { "Checking out #{current_branch}" }
        @git_repo.checkout current_branch
      end
    end

    # Get the log history of the supplied file as an array of
    # hashes, each entry has keys:
    # sha
    # date
    # author
    # email
    # parent
    # message
    def file_log(filename)
      o, e, s = exec_cmd("log", %w[--follow --date=iso --], "'#{filename}'")
      raise "Failed to get git log for #{filename}!!\n#{e}" if s.exitstatus != 0

      process_log_output(o)
    end

    # Public: Find the root directory of the git repo in which the
    #         given dirpath resides.
    #
    # dirpath - an absolute path to a directory that resides
    #           within a git repo.
    #
    # Returns: the root direcotry of the git repo or nil if the input path
    #          does not reside within a git repo.
    def find_gitrepo_root(dirpath)
      Pathname.new(dirpath).realpath.ascend do |p|
        git_dir = p.join(".git")
        return p if git_dir.directory?
      end
    end

    private

    def sync_treeish(b)
      Giblog.logger.info { "Checking out #{b.name}" }
      @git_repo.checkout b.name

      # merge branches with their upstream at origin unless
      # 'only local'
      unless (b.respond_to?(:tag?) && b.tag?) || @local_only
        # this is a branch, make sure it is up-to-date
        Giblog.logger.info { "Merging with origin/#{b.name}" }
        @git_repo.merge "origin/#{b.name}"
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
      Giblog.logger.debug { "selected git branches: #{user_checkouts}" }
      user_checkouts
    end

    def select_user_tags(regexp)
      return [] unless regexp

      @git_repo.tags.select do |t|
        regexp.match t.name
      end
    end

    # Process the log output from git
    # (This is copied to 90% from the ruby-git gem)
    def process_log_output(output)
      in_message = false
      hsh_array = []
      hsh = nil

      output.each_line do |line|
        line = line.chomp

        if line[0].nil?
          in_message = !in_message
          next
        end

        if in_message
          hsh["message"] << "#{line[4..]}\n"
          next
        end

        key, *value = line.split
        key = key.sub(":", "").downcase
        value = value.join(" ")

        case key
        when "commit"
          hsh_array << hsh if hsh
          hsh = {"sha" => value, "message" => +"", "parent" => []}
        when "parent"
          hsh["parent"] << value
        when "author"
          tmp = value.split("<")
          hsh["author"] = tmp[0].strip
          hsh["email"] = tmp[1].sub(">", "").strip
        when "date"
          hsh["date"] = DateTime.parse(value)
        else
          hsh[key] = value
        end
      end
      hsh_array << hsh if hsh
      hsh_array
    end

    # Execute engine for git commands,
    # Returns same as capture3 (stdout, stderr, Process.Status)
    def exec_cmd(cmd, flags, args)
      # always add the git dir to the cmd to ensure that git is executed
      # within the expected repo
      gd_flag = "--git-dir=\"#{@git_dir}\""
      wt_flag = "--work-tree=\"#{@repo_root}\""
      flag_str = flags.join(" ")
      git_cmd = "git #{gd_flag} #{wt_flag} #{cmd} #{flag_str} #{args}"
      Giblog.logger.debug { "running: #{git_cmd}" }
      Open3.capture3(git_cmd.to_s)
    end
  end
end
