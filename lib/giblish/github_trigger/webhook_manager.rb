require "git"
require_relative "../application"

module Giblish
  # Generate documentation using giblish when triggered by matching refs given to the 'run' method 
  class WebhookManager
    def initialize(ref_regexp, main_repo_url, repo_dir, repo_name, rel_src_doc, abs_dst_doc, logger)
      @ref_regexp = ref_regexp
      @main_repo_url = main_repo_url
      @rel_src_doc = rel_src_doc
      @dstdir = abs_dst_doc
      @logger = logger

      @repo_root = clone(main_repo_url, repo_dir, repo_name)
    end

    def run(github_hash)
      ref = github_hash.fetch(:ref).sub("refs/heads/", "")
      if ref.empty? || !(@ref_regexp =~ ref)
        @logger&.info { "Ref '#{ref}' does not match the document generation trigger. No document generation trted" }
        return
      end

      generate_docs(ref)
    end

    private

    def clone(main_repo_url, dst_dir, repo_name)
      p = Pathname.new(dst_dir).join(repo_name)

      repo = Git.clone(main_repo_url, repo_name, path: dst_dir.to_s, logger: @logger)
      repo.config("user.name", "Giblish Webhook Manager")
      repo.config("user.email", "dummy@giblish.com")
      p
    end

    def generate_docs(ref)
      srcdir = @repo_root.join(@rel_src_doc)
      args = %W[-f html -m --copy-asset-folders "_assets$" --server-search-path "/gibsearch" -g #{@ref_regexp} #{srcdir} #{@dstdir}]
      EntryPoint.run(args)
    end
  end
end
