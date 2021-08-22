require "oga"
require "test_helper"
require_relative "../lib/giblish/utils"
require_relative "../lib/giblish/docid"

# tests logging of giblish and asciidoc messages
class LoggingTest < Minitest::Test
  include Giblish::TestUtils

  @@doc_str = <<~EOF
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
      # adoc_filename = tmp_docs.add_doc_from_str @@doc_str
      args = [tmp_docs.dir,
        tmp_docs.dir]
      assert(Giblish.application.run args)
      assert(raise NotImplementedError)
    end
  end
end
