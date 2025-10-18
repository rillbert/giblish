# frozen_string_literal: true

require_relative "lib/gran/version"

Gem::Specification.new do |spec|
  spec.required_ruby_version = ">= 3.3.0"
  spec.name = "gran"
  spec.version = Gran::VERSION
  spec.authors = ["Anders Rillbert"]
  spec.email = ["anders.rillbert@kutso.se"]

  spec.summary = "Provides utility classes for working with trees of file paths"
  spec.description = "Provides classes for creatting and transforming trees of PathName nodes"
  spec.homepage = "https://github.com/rillbert/giblish/tree/main/gran"
  spec.license = "MIT"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "bug_tracker_uri" => "https://github.com/rillbert/giblish/issues",
    "source_code_uri" => "https://github.com/rillbert/giblish",
    "allowed_push_host" => "https://rubygems.org"
  }

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
