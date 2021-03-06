# frozen_string_literal: true

require "test_helper"
require_relative "../lib/giblish/utils"
require_relative "../lib/giblish/core"

class GiblishAdminTest < Minitest::Test
  def setup
    # setup logging
    Giblog.setup
  end

  def test_that_it_has_a_version_number
    refute_nil ::Giblish::VERSION
  end
end

class PathManagerTest < Minitest::Test
  include Giblish::TestUtils

  def setup
    # setup logging
    Giblog.setup
  end
end
