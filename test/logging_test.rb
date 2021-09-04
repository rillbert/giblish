require "oga"
require "test_helper"
require_relative "../lib/giblish/utils"

# tests logging of giblish and asciidoc messages
class LoggingTest < Minitest::Test
  include Giblish::TestUtils

  TEST_DOC = <<~EOF
    = Test logging
    :numbered:

    == The first section

    some random text..

    ==== A section one lovel too deep

    An invalid reference: <<_the_first>>.
  EOF

  def setup
    # setup logging
    Giblog.setup
  end

  def test_logging_of_info_and_warn
    TmpDocDir.open do |tmp_docs|
      srcdir = Pathname.new(tmp_docs.dir)
      tmp_docs.create_adoc_src_on_disk(srcdir, {doc_src: TEST_DOC})
      args = [srcdir, srcdir]
      assert(Giblish.application.run(args))
      # TODO: Find a good way of testing this !!
    end
  end
end
