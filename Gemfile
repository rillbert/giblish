source "https://rubygems.org"

# Use the gemspec for all runtime dependencies and other
# metadata on the gem
gemspec

group :development, :test do
  gem "yard", "~> 0.9"
  gem "ruby-lsp", "~> 0.18"
  gem "standard", "~> 1.0"
  gem "rake", "~> 13.0"
  gem "oga", "~> 3.0"
  gem "thor", "~> 1.0"
  gem "asciidoctor-mathematical", "~> 0.3.5"

  # needed for the sinatra-based apps
  gem "sinatra", "~> 2.0"
  gem "thin", "~> 1.0"
  gem "rack", "~> 2.2"
  gem "rack-test", "~> 1.1"
end

group :test do
  gem "minitest", "~> 5.0"
end
