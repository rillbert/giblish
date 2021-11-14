lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "giblish/version"

Gem::Specification.new do |spec|
  spec.name = "giblish"
  spec.version = Giblish::VERSION
  spec.authors = ["Anders Rillbert"]
  spec.email = ["anders.rillbert@kutso.se"]

  spec.summary = "A tool for publishing asciidoc docs stored in git repos"
  spec.description = <<~EOF
    giblish generates indexed and searchable documents from a tree of
    asciidoc files.
  EOF
  spec.homepage = "https://github.com/rillbert/giblish"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  # if spec.respond_to?(:metadata)
  #   spec.metadata['allowed_push_host'] = "https://gems.my-company.example"
  # else
  #   raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  # end

  spec.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 2.1"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "standard", "~> 1.1"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "oga", "~> 3.3"
  spec.add_development_dependency 'thor', '~> 0.20.3'
  spec.add_development_dependency "asciidoctor-mathematical", "~> 0.3.5"
  # needed for the sinatra-based apps
  spec.add_development_dependency "sinatra", "~>2.1"
  spec.add_development_dependency "thin", "~>1.8"
  spec.add_development_dependency "rack", "2.2.3"
  spec.add_development_dependency "rack-test", "1.1"
  

  # Used during run-time by giblish
  spec.add_runtime_dependency "warning", "~>1.2"
  spec.add_runtime_dependency "asciidoctor", "~>2.0", ">= 2.0.16"
  spec.add_runtime_dependency "asciidoctor-diagram", ["~> 2.2"]
  spec.add_runtime_dependency "asciidoctor-pdf", ["~> 1.6", ">= 1.6.1"]
  spec.add_runtime_dependency "git", "~> 1.9"
  spec.add_runtime_dependency "rouge", "~> 3.0"
  spec.add_runtime_dependency "prawn-svg", "~> 0.32.0"
end
