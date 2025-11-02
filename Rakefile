# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc "Build gem"
task :build do
  sh "gem build query_guard.gemspec"
end

desc "Release: build and push to RubyGems"
task :release do
  version = File.read("lib/query_guard/version.rb")[/VERSION\s*=\s*["'](.+?)["']/, 1]
  abort("Version not found") unless version
  sh "gem build query_guard.gemspec"
  sh "gem push query_guard-#{version}.gem"
end
