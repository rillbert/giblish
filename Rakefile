require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

Rake::TestTask.new(:current) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/docid_test.rb"]
end

Rake::TestTask.new(:sandbox) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/sandbox_test.rb"]
end


# task :default => :spec
task :default => :test
