require "rake/testtask"
require "standard/rake"

Rake::TestTask.new(:giblish) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

Rake::TestTask.new(:sinatra) do |t|
  t.libs << "test"
  t.libs << "web_apps/sinatra_search"
  t.test_files = FileList["apps/test/**/*_test.rb"]
end

Rake::TestTask.new(:all) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.libs << "web_apps/sinatra_search"
  t.test_files = FileList["test/**/*_test.rb"]
end

# task :default => :spec
task default: :all
task test: :all
