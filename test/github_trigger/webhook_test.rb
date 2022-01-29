require "json"
require_relative "../test_helper"
require_relative "../../lib/giblish/github_trigger/webhook_manager"

module Giblish
  class WebHookTest < GiblishTestBase
    include Giblish::TestUtils

    # an example payload from github as read by
    # 'request.body.read'
    GH_PUSH_JSON = <<~GH_JSON
      {
        "ref": "refs/heads/personal/rillbert/svg_index",
        "before": "bcc68b29b17b02452e2bc10aad29b122aebafa4e",
        "after": "54dbb77d78a4050e59dc0227dda59400a1a09a4a",
        "repository": {
          "id": 95320718,
          "node_id": "MDEwOlJlcG9zaXRvcnk5NTMyMDcxOA==",
          "name": "giblish",
          "full_name": "rillbert/giblish",
          "private": false,
          "owner": {
            "name": "rillbert",
            "email": "anders.rillbert@kutso.se",
            "login": "rillbert",
            "id": 29681033,
            "node_id": "MDQ6VXNlcjI5NjgxMDMz",
            "avatar_url": "https://avatars.githubusercontent.com/u/29681033?v=4",
            "gravatar_id": "",
            "url": "https://api.github.com/users/rillbert",
            "html_url": "https://github.com/rillbert",
            "followers_url": "https://api.github.com/users/rillbert/followers",
            "following_url": "https://api.github.com/users/rillbert/following{/other_user}",
            "gists_url": "https://api.github.com/users/rillbert/gists{/gist_id}",
            "starred_url": "https://api.github.com/users/rillbert/starred{/owner}{/repo}",
            "subscriptions_url": "https://api.github.com/users/rillbert/subscriptions",
            "organizations_url": "https://api.github.com/users/rillbert/orgs",
            "repos_url": "https://api.github.com/users/rillbert/repos",
            "events_url": "https://api.github.com/users/rillbert/events{/privacy}",
            "received_events_url": "https://api.github.com/users/rillbert/received_events",
            "type": "User",
            "site_admin": false
          },
          "html_url": "https://github.com/rillbert/giblish",
          "description": "A tool for publishing asciidoc trees in git repos as html or pdf",
          "fork": false,
          "url": "https://github.com/rillbert/giblish",
          "forks_url": "https://api.github.com/repos/rillbert/giblish/forks",
          "keys_url": "https://api.github.com/repos/rillbert/giblish/keys{/key_id}",
          "collaborators_url": "https://api.github.com/repos/rillbert/giblish/collaborators{/collaborator}",
          "teams_url": "https://api.github.com/repos/rillbert/giblish/teams",
          "hooks_url": "https://api.github.com/repos/rillbert/giblish/hooks",
          "issue_events_url": "https://api.github.com/repos/rillbert/giblish/issues/events{/number}",
          "events_url": "https://api.github.com/repos/rillbert/giblish/events",
          "assignees_url": "https://api.github.com/repos/rillbert/giblish/assignees{/user}",
          "branches_url": "https://api.github.com/repos/rillbert/giblish/branches{/branch}",
          "tags_url": "https://api.github.com/repos/rillbert/giblish/tags",
          "blobs_url": "https://api.github.com/repos/rillbert/giblish/git/blobs{/sha}",
          "git_tags_url": "https://api.github.com/repos/rillbert/giblish/git/tags{/sha}",
          "git_refs_url": "https://api.github.com/repos/rillbert/giblish/git/refs{/sha}",
          "trees_url": "https://api.github.com/repos/rillbert/giblish/git/trees{/sha}",
          "statuses_url": "https://api.github.com/repos/rillbert/giblish/statuses/{sha}",
          "languages_url": "https://api.github.com/repos/rillbert/giblish/languages",
          "stargazers_url": "https://api.github.com/repos/rillbert/giblish/stargazers",
          "contributors_url": "https://api.github.com/repos/rillbert/giblish/contributors",
          "subscribers_url": "https://api.github.com/repos/rillbert/giblish/subscribers",
          "subscription_url": "https://api.github.com/repos/rillbert/giblish/subscription",
          "commits_url": "https://api.github.com/repos/rillbert/giblish/commits{/sha}",
          "git_commits_url": "https://api.github.com/repos/rillbert/giblish/git/commits{/sha}",
          "comments_url": "https://api.github.com/repos/rillbert/giblish/comments{/number}",
          "issue_comment_url": "https://api.github.com/repos/rillbert/giblish/issues/comments{/number}",
          "contents_url": "https://api.github.com/repos/rillbert/giblish/contents/{+path}",
          "compare_url": "https://api.github.com/repos/rillbert/giblish/compare/{base}...{head}",
          "merges_url": "https://api.github.com/repos/rillbert/giblish/merges",
          "archive_url": "https://api.github.com/repos/rillbert/giblish/{archive_format}{/ref}",
          "downloads_url": "https://api.github.com/repos/rillbert/giblish/downloads",
          "issues_url": "https://api.github.com/repos/rillbert/giblish/issues{/number}",
          "pulls_url": "https://api.github.com/repos/rillbert/giblish/pulls{/number}",
          "milestones_url": "https://api.github.com/repos/rillbert/giblish/milestones{/number}",
          "notifications_url": "https://api.github.com/repos/rillbert/giblish/notifications{?since,all,participating}",
          "labels_url": "https://api.github.com/repos/rillbert/giblish/labels{/name}",
          "releases_url": "https://api.github.com/repos/rillbert/giblish/releases{/id}",
          "deployments_url": "https://api.github.com/repos/rillbert/giblish/deployments",
          "created_at": 1498335662,
          "updated_at": "2021-09-09T18:20:50Z",
          "pushed_at": 1636038329,
          "git_url": "git://github.com/rillbert/giblish.git",
          "ssh_url": "git@github.com:rillbert/giblish.git",
          "clone_url": "https://github.com/rillbert/giblish.git",
          "svn_url": "https://github.com/rillbert/giblish",
          "homepage": null,
          "size": 3368,
          "stargazers_count": 4,
          "watchers_count": 4,
          "language": "Ruby",
          "has_issues": true,
          "has_projects": true,
          "has_downloads": true,
          "has_wiki": true,
          "has_pages": false,
          "forks_count": 1,
          "mirror_url": null,
          "archived": false,
          "disabled": false,
          "open_issues_count": 2,
          "license": {
            "key": "mit",
            "name": "MIT License",
            "spdx_id": "MIT",
            "url": "https://api.github.com/licenses/mit",
            "node_id": "MDc6TGljZW5zZTEz"
          },
          "allow_forking": true,
          "is_template": false,
          "topics": [],
          "visibility": "public",
          "forks": 1,
          "open_issues": 2,
          "watchers": 4,
          "default_branch": "main",
          "stargazers": 4,
          "master_branch": "main"
        },
        "pusher": {
          "name": "rillbert",
          "email": "anders.rillbert@kutso.se"
        },
        "sender": {
          "login": "rillbert",
          "id": 29681033,
          "node_id": "MDQ6VXNlcjI5NjgxMDMz",
          "avatar_url": "https://avatars.githubusercontent.com/u/29681033?v=4",
          "gravatar_id": "",
          "url": "https://api.github.com/users/rillbert",
          "html_url": "https://github.com/rillbert",
          "followers_url": "https://api.github.com/users/rillbert/followers",
          "following_url": "https://api.github.com/users/rillbert/following{/other_user}",
          "gists_url": "https://api.github.com/users/rillbert/gists{/gist_id}",
          "starred_url": "https://api.github.com/users/rillbert/starred{/owner}{/repo}",
          "subscriptions_url": "https://api.github.com/users/rillbert/subscriptions",
          "organizations_url": "https://api.github.com/users/rillbert/orgs",
          "repos_url": "https://api.github.com/users/rillbert/repos",
          "events_url": "https://api.github.com/users/rillbert/events{/privacy}",
          "received_events_url": "https://api.github.com/users/rillbert/received_events",
          "type": "User",
          "site_admin": false
        },
        "created": false,
        "deleted": false,
        "forced": false,
        "base_ref": null,
        "compare": "https://github.com/rillbert/giblish/compare/bcc68b29b17b...54dbb77d78a4",
        "commits": [
          {
            "id": "54dbb77d78a4050e59dc0227dda59400a1a09a4a",
            "tree_id": "38c5304462d3b20725d3d9371a472f36a660e12a",
            "distinct": true,
            "message": "start implementing gh webhook",
            "timestamp": "2021-11-04T16:05:25+01:00",
            "url": "https://github.com/rillbert/giblish/commit/54dbb77d78a4050e59dc0227dda59400a1a09a4a",
            "author": {
              "name": "Anders Rillbert",
              "email": "anders.rillbert@kutso.se",
              "username": "rillbert"
            },
            "committer": {
              "name": "Anders Rillbert",
              "email": "anders.rillbert@kutso.se",
              "username": "rillbert"
            },
            "added": [
              "lib/giblish/github_trigger/webhook_manager.rb",
              "test/github_trigger/webhook_test.rb"
            ],
            "removed": [],
            "modified": [
              "apps/gh_webhook_trigger/gh_webhook_trigger.rb"
            ]
          }
        ],
        "head_commit": {
          "id": "54dbb77d78a4050e59dc0227dda59400a1a09a4a",
          "tree_id": "38c5304462d3b20725d3d9371a472f36a660e12a",
          "distinct": true,
          "message": "start implementing gh webhook",
          "timestamp": "2021-11-04T16:05:25+01:00",
          "url": "https://github.com/rillbert/giblish/commit/54dbb77d78a4050e59dc0227dda59400a1a09a4a",
          "author": {
            "name": "Anders Rillbert",
            "email": "anders.rillbert@kutso.se",
            "username": "rillbert"
          },
          "committer": {
            "name": "Anders Rillbert",
            "email": "anders.rillbert@kutso.se",
            "username": "rillbert"
          },
          "added": [
            "lib/giblish/github_trigger/webhook_manager.rb",
            "test/github_trigger/webhook_test.rb"
          ],
          "removed": [],
          "modified": [
            "apps/gh_webhook_trigger/gh_webhook_trigger.rb"
          ]
        }
      }    
    GH_JSON

    def test_get_ref
      no_trig_push = {
        ref: "refs/heads/master"
      }
      trig_push = {
        ref: "refs/heads/svg_index"
      }
      TmpDocDir.open(preserve: false) do |tmp_docs|
        topdir = Pathname.new(tmp_docs.dir)
        dstdir = topdir.join("html")

        wm = GenerateFromRefs.new(
          "https://github.com/rillbert/giblish.git",
          /svg/,
          topdir,
          "giblish",
          "docs",
          dstdir,
          Giblog.logger
        )
        wm.docs_from_gh_webhook(no_trig_push)
        assert(!dstdir.exist?)

        wm.docs_from_gh_webhook(trig_push)
        result = PathTree.build_from_fs(dstdir, prune: true)
        puts result.to_s
        assert(result.node("index.html"))
        assert(result.node("personal_rillbert_svg_index"))
        assert(result.node("personal_rillbert_svg_index/reference/search_spec.html"))
      end
    end
  end
end
