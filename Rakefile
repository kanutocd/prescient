# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "rubocop/rake_task"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

RuboCop::RakeTask.new

desc "Run tests and linting"
task default: %w[test rubocop]

desc "Run tests with coverage"
task :coverage do
  ENV['COVERAGE'] = 'true'
  Rake::Task[:test].execute
end

desc "Console with gem loaded"
task :console do
  require "bundler/setup"
  require "prescient"
  require "irb"
  ARGV.clear
  IRB.start
end
