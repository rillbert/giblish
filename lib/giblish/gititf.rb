require "open3"
require_relative "utils"

module Giblish
  # A home-grown interface class to git. Used for situations when the
  # 'official' ruby git gem does not support an operation that is needed.
  class GitItf
    attr_reader :repo_root
    attr_reader :git_dir

    def initialize(path)
      @repo_root = Giblish::PathManager.find_gitrepo_root(path)
      if @repo_root.nil?
        raise ArgumentError("The path: @{path} is not within a git repo!")
      end
      @git_dir = @repo_root + ".git"
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
      o, e, s = exec_cmd("log", %w[--follow --date=iso --], filename)
      raise "Failed to get git log for #{filename}!!\n#{e}" if s.exitstatus != 0

      process_log_output(o)
    end

    private

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
          hsh["message"] << "#{line[4..-1]}\n"
          next
        end

        key, *value = line.split
        key = key.sub(":", "").downcase
        value = value.join(" ")

        case key
        when "commit"
          hsh_array << hsh if hsh
          hsh = { "sha" => value, "message" => "", "parent" => [] }
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
