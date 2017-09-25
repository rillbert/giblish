# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'giblish/version'

Gem::Specification.new do |spec|
  spec.name          = "giblish"
  spec.version       = Giblish::VERSION
  spec.authors       = ["Anders Rillbert"]
  spec.email         = ["anders.rillbert@kutso.se"]

  spec.summary       = %q{A tool for publishing asciidoc docs stored in git repos}
  spec.description   = %q{A tool for publishing asciidoc docs stored in git repos}
  spec.homepage      = "http://www.example.com"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  # if spec.respond_to?(:metadata)
  #   spec.metadata['allowed_push_host'] = "https://gems.my-company.example"
  # else
  #   raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  # end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"

  # Usage: spec.add_runtime_dependency "[gem name]", [[version]]
  spec.add_runtime_dependency "git", "~> 1.3"
  spec.add_runtime_dependency "asciidoctor", "~>1.5", ">= 1.5.6.1"
  spec.add_runtime_dependency "asciidoctor-pdf", [">= 1.5.0.alpha.16"]
  # needed by asciidoctor-pdf, see instructions at
  # https://github.com/asciidoctor/asciidoctor-pdf/releases
  spec.add_runtime_dependency "prawn-svg", "~> 0.27.1"
end
