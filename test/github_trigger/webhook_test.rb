require_relative "test_helper"
require_relative "../lib/giblish/github_trigger/webhook_manager"

module Giblish
  class WebHookTest < GiblishTestBase

    GH_PUSH_JSON = <<~GH_JSON
    GH_JSON

    def test_get_ref
      TmpDocDir.open(preserve: false) do |tmp_docs|
        assert(r.node("dst/web_assets/dir1"))
        assert(r.node("dst/web_assets/dir1/custom.css"))
      end
    end
  end
end
