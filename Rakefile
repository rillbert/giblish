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
  t.test_files = FileList["test/**/index_heading_test.rb"]
end

Rake::TestTask.new(:paths) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/pathmanager_test.rb"]
end

Rake::TestTask.new(:graph) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/depgraph_test.rb"]
end

Rake::TestTask.new(:css) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/linkcss_test.rb"]
end

Rake::TestTask.new(:sandbox) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/sandbox_test.rb"]
end


# task :default => :spec
task :default => :test
