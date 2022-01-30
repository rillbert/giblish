require "git"
require_relative "../application"

module Giblish
  # Generate documentation using giblish based on the supplied parameters
  class GenerateFromRefs
    STANDARD_GIBLISH_FLAGS = %W[-f html -m --copy-asset-folders _assets$ --server-search-path /cgi-bin/gibsearch.cgi]

    # doc_repo_url:: the url of the repo hosting the docs to be generated. this repo will be cloned
    # ref_regexp:: a regexp that both defines what git refs that trigger a document generation and what refs will be
    # generated.
    # clone_dir_parent:: path to the local directory under which the doc_repo_url will be cloned.
    # clone_name:: the name of the local clone of the doc_repo_url
    # doc_src_rel:: the relative path from the repo root to the directory where the docs reside
    # doc_dst_abs:: the absolute path to the target location for the generated docs
    # logger:: a ruby Logger instance that will receive log messages
    def initialize(doc_repo_url, ref_regexp, clone_dir_parent, clone_name, giblish_args, doc_src_rel, doc_dst_abs, logger)
      @doc_repo_url = doc_repo_url
      @ref_regexp = ref_regexp
      @giblish_args = STANDARD_GIBLISH_FLAGS
      @giblish_args += giblish_args unless giblish_args.nil?
      @doc_src_rel = doc_src_rel
      @dstdir = doc_dst_abs
      @logger = logger

      @repo_root = clone(doc_repo_url, clone_dir_parent, clone_name)
    end

    # Generate documents from the git refs found in the GitHub
    # webhook payload.
    def docs_from_gh_webhook(github_hash)
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
      @logger&.info { "Cloning done" }
      p
    end

    def generate_docs(ref)
      srcdir = @repo_root.join(@doc_src_rel)
      args = @giblish_args + %W[-g #{@ref_regexp} #{srcdir} #{@dstdir}]

      @logger&.info { "Generate docs using parameters: #{args}" }
      # run giblish with all args
      EntryPoint.run(args, @logger)
    end
  end
end
