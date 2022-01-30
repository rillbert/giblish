# frozen_string_literal: true

require "test_helper"
require_relative "../lib/giblish/utils"
require_relative "../lib/giblish/core"

class GiblishAdminTest < GiblishTestBase
  def test_that_it_has_a_version_number
    refute_nil ::Giblish::VERSION
  end
end
