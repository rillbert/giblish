require "open3"

require_relative "utils"

module Giblish
  class GitCommit
    attr_writer :commit
    attr_writer :author
    attr_writer :message
  end

  class GitItf

    attr_reader :repo_root
    attr_reader :git_dir

    def initialize(path)
      @repo_root = Giblish::PathManager.find_gitrepo_root(path)
      raise ArgumentError("The path: @{path} is not within a git repo!") if @repo_root.nil?
      @git_dir = @repo_root + ".git"
    end

    def file_log(filename)
      o, e, s = exec_cmd("log", %w[--follow --], filename)
      raise "Failed to get file log for #{filename}!!\n#{e}" if s.exitstatus != 0

      process_log_output(o)
    end

    private

    def process_log_output(output)
      tokens = { "commit" => :commit, "Author:" => :author }

      output.each_line do |l|
        if l.empty?
          token = message:
        end
        token, value = l.split

        puts ":#{l.chomp}:"
      end
    end

    def exec_cmd(cmd, flags, args)
      # always add the git dir to the cmd to ensure that git is executed
      # within the expected repo
      gd_flag = "--git-dir=#{@git_dir}"
      wt_flag = "--work-tree=#{@repo_root}"
      flag_str = flags.join(" ")
      git_cmd = "git #{gd_flag} #{wt_flag} #{cmd} #{flag_str} #{args}"
      puts "running: #{git_cmd}"
      # Open3.capture2(git_cmd.to_s)
      Open3.capture3(git_cmd.to_s,:binmode=>true)
    end

    # def commit_info(repo_root, file_path)
    #    o, _ = Open3.capture2(%Q[git --git-dir=#{repo_root}/.git log --date=short --format='- { !ruby/symbol author: %an, !ruby/symbol date: %ad, !ruby/symbol hash: %h, !ruby/symbol subject: %f }' -- #{file_path.to_s.sub(/#{repo_root}\//, '')}])
    #    YAML.parse o
    #  end
  end
end

# ../VironovaSW/Documents/process/product_pipeline.adoc
if __FILE__ == $PROGRAM_NAME
  # gi = Giblish::GitItf.new(".")
  gi = Giblish::GitItf.new("../VironovaSW/Documents/process")
  gi.file_log("Analyzer/Vironova.Analyzer/MainForm.cs")
end
