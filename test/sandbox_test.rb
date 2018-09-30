require "test_helper"
require "pp"
require_relative "../lib/giblish.rb"

class RunGiblishTest < Minitest::Test
  def test_access_git_itf_members

#    @git_repo_root = "../giblish-testdata"
#    @git_repo_root = "."
#    @git_repo_root = "../../vc/vas_minitem/"
    # Connect to the git repo

    # begin
    #   @git_repo = Git.open(@git_repo_root)
    # rescue Exception => e
    #   raise "Could not find a git repo at #{@git_repo_root} !"\
    #         "\n\n(#{e.message})"
    # end
    #
    # puts "checking tags..."
    # @user_tags = @git_repo.tags.select do |t|
    #   if t.name =~ /.*$/ && t.annotated?
    #     puts "Tag #{t.name} created by #{t.tagger.name} at #{t.tagger.date} with message: #{t.message}"
    #   else
    #     t = @git_repo.tag(t.name)
    #     puts "Tag #{t.name}"
    #   end
    #   c = @git_repo.gcommit(t.sha)
    #   puts "Tags commit #{t.sha[0,8]}... which was committed at #{c.author.date}"
    # end
  end
end