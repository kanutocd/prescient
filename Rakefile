# frozen_string_literal: true

require "bundler/gem_tasks"
require "rbconfig"
require "rake/testtask"
require "rubocop/rake_task"
require "yard"
require "yard/rake/yardoc_task"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ["--parallel"]
end

YARD::Rake::YardocTask.new(:yard)
namespace :yard do
  desc "Validate YARD documentation coverage"
  task :validate do
    require "open3"

    stdout, stderr, status = Open3.capture3("bundle", "exec", "yard", "stats")
    text = "#{stdout}\n#{stderr}"
    puts text
    abort("yard stats failed") unless status.success?

    match = text.match(/([0-9]+(?:\.[0-9]+)?)%\s+documented/)
    abort("Unable to determine YARD coverage") unless match

    coverage = match[1].to_f
    minimum = 99.0
    if coverage < minimum
      message = format(
        "YARD coverage %<coverage>.2f%% is below %<minimum>.2f%%",
        coverage: coverage,
        minimum: minimum
      )
      abort(message)
    end

    puts format("YARD coverage %.2f%%", coverage)
  end
end

namespace :rbs do
  desc "Remove generated RBS prototype files"
  task :clobber do
    sh "rm -rf tmp/sig"
  end

  desc "Generate disposable RBS prototypes into tmp/sig"
  task :prototype do
    sh "rm -rf tmp/sig"
    sh "mkdir -p tmp/sig"
    sh "bundle exec rbs prototype rb --out-dir=tmp/sig --base-dir=lib lib"
  end

  desc "Validate curated RBS signatures with Steep"
  task :validate do
    sh "bundle exec steep check"
  end

  desc "Open diff between curated and generated signatures"
  task :diff do
    sh "diff -ru sig tmp/sig || true"
  end

  desc "Generate disposable RBS prototypes and validate curated signatures"
  task check: %i[prototype validate]
end

namespace :examples do
  desc "Validate Ruby example syntax without contacting providers"
  task :syntax do
    Dir["examples/**/*.rb"].sort.each do |file|
      sh RbConfig.ruby, "-c", file
    end
  end
end

desc "Validate GitHub Actions workflows"
task :actionlint do
  actionlint = if File.executable?(".tools/bin/actionlint")
                 ".tools/bin/actionlint"
               else
                 ENV.fetch("ACTIONLINT", "actionlint")
               end
  sh actionlint
end


desc "Run tests and linting"
task default: %w[test rubocop yard yard:validate rbs:validate examples:syntax]

desc "Console with gem loaded"
task :console do
  require "bundler/setup"
  require "prescient"
  require "irb"
  ARGV.clear
  IRB.start
end
