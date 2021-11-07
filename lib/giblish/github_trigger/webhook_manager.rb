require "git"
require_relative "../application"

module Giblish
  # Generate documentation using giblish when triggered by matching refs given to the 'run' method 
  class WebhookManager
    STANDARD_GIBLISH_FLAGS = %W[-f html -m --copy-asset-folders "_assets$" --server-search-path "/gibsearch"]

    # ref_regexp:: a regexp that both defines what git refs that trigger a document generation and what refs will be 
    # generated.
    # doc_repo_url:: the url of the repo hosting the docs to be generated
    # clone_dir_parent:: path to the local directory under which the doc_repo_url will be cloned.
    # clone_name:: the name of the local clone of the doc_repo_url
    # doc_src_rel:: the relative path from the repo root to the directory where the docs reside
    # doc_dst_abs:: the absolute path to the target location for the generated docs
    # logger:: a ruby Logger instance that will receive log messages
    def initialize(ref_regexp, doc_repo_url, clone_dir_parent, clone_name, doc_src_rel, doc_dst_abs, logger)
      @ref_regexp = ref_regexp
      @doc_repo_url = doc_repo_url
      @doc_src_rel = doc_src_rel
      @dstdir = doc_dst_abs
      @logger = logger

      @repo_root = clone(doc_repo_url, clone_dir_parent, clone_name)
    end

    def run(github_hash)
      # TODO Implement support for other refs than branches
      ref = github_hash.fetch(:ref).sub("refs/heads/", "")
      if ref.empty? || !(@ref_regexp =~ ref)
        @logger&.info { "Ref '#{ref}' does not match the document generation trigger -> No document generation triggereed" }
        return
      end

      generate_docs(ref)
    end

    private

    def clone(doc_repo_url, dst_dir, clone_name)
      p = Pathname.new(dst_dir).join(clone_name)

      @logger&.info { "Cloning #{doc_repo_url} to #{p}..." }
      repo = Git.clone(doc_repo_url, clone_name, path: dst_dir.to_s, logger: @logger)
      repo.config("user.name", "Giblish Webhook Manager")
      repo.config("user.email", "dummy@giblish.com")
      @logger&.info { "Cloning done"}
      p
    end

    def generate_docs(ref)
      srcdir = @repo_root.join(@doc_src_rel)
      args = STANDARD_GIBLISH_FLAGS + %W[-g #{@ref_regexp} #{srcdir} #{@dstdir}]

      @logger&.info { "Generate docs using parameters: #{args}" }
      # run giblish with all args
      EntryPoint.run(args, @logger)
    end
  end
end
