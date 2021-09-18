require_relative "test_helper"
require_relative "../lib/giblish/config_utils"
require_relative "../lib/giblish/docattr_providers"

module Giblish
  class ConfigurationTest < Minitest::Test
    include Giblish::TestUtils

    def test_merge_doc_attribs
      # basic test
      builder = DocAttrBuilder.new(
        AbsoluteLinkedCss.new("my/css/path")
      )
      assert_equal(
        {
          "stylesdir" => "my/css",
          "stylesheet" => "path",
          "linkcss" => true,
          "copycss" => nil
        },
        builder.document_attributes(nil, nil, nil)
      )

      # adding a new version will overwrite existing attribs
      # if they correspond to existing and adding new ones
      builder.add_doc_attr_providers(
        AbsoluteLinkedCss.new("my/new/css"),
        GiblishDefaultDocAttribs.new
      )
      assert_equal(
        {
          "stylesdir" => "my/new",
          "stylesheet" => "css",
          "linkcss" => true,
          "copycss" => nil,
          "source-highlighter" => "rouge",
          "xrefstyle" => "short"
        },
        builder.document_attributes(nil, nil, nil)
      )
    end

    def test_raise_non_compliant
      assert_raises(ArgumentError) { DocAttrBuilder.new(self) }
    end

    def test_doc_attr_config
      # start with default attributes
      ab = DocAttrBuilder.new(GiblishDefaultDocAttribs.new)
      attrs = ab.document_attributes(nil, nil, nil)
      assert_equal("short", attrs["xrefstyle"])

      # override with cmd line opts
      cmd_opts = CmdLine.new.parse(%W[-a xrefstyle=custom -a attr1=value1 -a attr2=value2 #{__dir__} #{__dir__}])
      ab.add_doc_attr_providers(CmdLineDocAttribs.new(cmd_opts))
      attrs = ab.document_attributes(nil, nil, nil)
      assert_equal("custom", attrs["xrefstyle"])
      assert_equal("value1", attrs["attr1"])
    end
  end
end
