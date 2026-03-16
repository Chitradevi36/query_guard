#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual test runner without RSpec dependency
$LOAD_PATH.unshift File.expand_path('lib', __dir__)

require 'query_guard'
require 'query_guard/migrations/migration_risk_detectors'
require 'query_guard/migrations/migration_analyzer'

class SimpleTestRunner
  attr_reader :total_tests, :passed_tests, :failed_tests

  def initialize
    @total_tests = 0
    @passed_tests = 0
    @failed_tests = 0
    @failures = []
  end

  def test(description)
    @total_tests += 1
    begin
      yield
      @passed_tests += 1
      puts "  ✓ #{description}"
    rescue AssertionError => e
      @failed_tests += 1
      puts "  ✗ #{description}"
      @failures << "#{description}: #{e.message}"
    end
  end

  def assert_equal(actual, expected, message = "")
    unless actual == expected
      raise AssertionError, "Expected #{expected.inspect}, got #{actual.inspect}. #{message}"
    end
  end

  def assert_includes(collection, item, message = "")
    unless collection.include?(item)
      raise AssertionError, "Expected #{collection.inspect} to include #{item.inspect}. #{message}"
    end
  end

  def assert_not_empty(collection, message = "")
    if collection.empty?
      raise AssertionError, "Expected #{collection.inspect} to not be empty. #{message}"
    end
  end

  def assert_empty(collection, message = "")
    unless collection.empty?
      raise AssertionError, "Expected #{collection.inspect} to be empty. #{message}"
    end
  end

  def assert_true(value, message = "")
    unless value
      raise AssertionError, "Expected #{value.inspect} to be true. #{message}"
    end
  end

  def summary
    puts ""
    puts "=" * 60
    puts "Test Summary: #{@passed_tests}/#{@total_tests} passed"
    puts "=" * 60
    
    if @failed_tests > 0
      puts "\nFailures:"
      @failures.each { |f| puts "  • #{f}" }
      return false
    end
    true
  end

  class AssertionError < StandardError; end
end

runner = SimpleTestRunner.new
fixture_migrations_dir = File.expand_path('spec/migrations/fixture_migrations', __dir__)
analyzer = QueryGuard::Migrations::MigrationAnalyzer.new

puts "Running Migration Analyzer Tests"
puts "=" * 60

puts "\n#analyze_migration"

runner.test("detects unsafe add_index without concurrently") do
  migration_file = File.join(fixture_migrations_dir, "20240101000001_create_users_table.rb")
  findings = analyzer.analyze_migration(migration_file)
  
  index_findings = findings.select { |f| f.rule_name == :index_not_concurrent }
  runner.assert_equal(index_findings.count, 2, "Should find 2 unsafe indexes")
  runner.assert_equal(index_findings.first.severity, :error)
  runner.assert_true(index_findings.first.title.include?("Index Addition Without CONCURRENTLY"))
end

runner.test("detects non-null column without default") do
  migration_file = File.join(fixture_migrations_dir, "20240102000001_add_status_to_users.rb")
  findings = analyzer.analyze_migration(migration_file)
  
  non_null_findings = findings.select { |f| f.rule_name == :non_null_no_default }
  runner.assert_not_empty(non_null_findings)
  
  finding = non_null_findings.first
  runner.assert_equal(finding.severity, :error)
  runner.assert_true(finding.title.include?("Non-NULL Column Without Default"))
end

runner.test("detects column type changes") do
  migration_file = File.join(fixture_migrations_dir, "20240103000001_change_email_type_on_users.rb")
  findings = analyzer.analyze_migration(migration_file)
  
  change_findings = findings.select { |f| f.rule_name == :change_column_lock }
  runner.assert_not_empty(change_findings)
  
  finding = change_findings.first
  runner.assert_equal(finding.severity, :error)
  runner.assert_true(finding.title.include?("Column Type Change Locks Table") || finding.title.include?("Change Column Locks Table"))
  runner.assert_equal(finding.metadata[:operation], "change_column")
end

runner.test("detects full-table updates") do
  migration_file = File.join(fixture_migrations_dir, "20240104000001_populate_status_on_users.rb")
  findings = analyzer.analyze_migration(migration_file)
  
  update_findings = findings.select { |f| f.rule_name == :full_table_update }
  runner.assert_not_empty(update_findings)
  
  finding = update_findings.first
  runner.assert_equal(finding.severity, :error)
  runner.assert_true(finding.title.include?("Full-Table Update in Migration") || finding.title.include?("Full-Table Update"))
end

runner.test("detects dangerous raw SQL") do
  migration_file = File.join(fixture_migrations_dir, "20240105000001_migrate_old_data.rb")
  findings = analyzer.analyze_migration(migration_file)
  
  # Should find at least 2 dangerous SQL risks
  sql_findings = findings.select { |f| f.rule_name == :dangerous_raw_sql || f.rule_name == :unsafe_raw_sql_full_table }
  runner.assert_equal(sql_findings.count >= 2, true, "Should find at least 2 dangerous SQL risks, found: #{sql_findings.count}")
end

runner.test("detects remove_column operations") do
  migration_file = File.join(fixture_migrations_dir, "20240106000001_remove_and_rename_columns.rb")
  findings = analyzer.analyze_migration(migration_file)
  
  remove_findings = findings.select { |f| f.rule_name == :remove_column_lock }
  runner.assert_not_empty(remove_findings)
  
  finding = remove_findings.first
  runner.assert_equal(finding.severity, :error)
  runner.assert_true(finding.title.include?("Column Removal") || finding.title.include?("remove_column") || finding.title.include?("Remove Column"))
end

runner.test("detects rename_column operations") do
  migration_file = File.join(fixture_migrations_dir, "20240106000001_remove_and_rename_columns.rb")
  findings = analyzer.analyze_migration(migration_file)
  
  rename_findings = findings.select { |f| f.rule_name == :rename_column_lock }
  runner.assert_not_empty(rename_findings)
  
  finding = rename_findings.first
  runner.assert_equal(finding.severity, :warn)
  runner.assert_true(finding.title.include?("Rename") || finding.title.include?("rename_column"))
end

runner.test("does not flag safe concurrent index addition") do
  migration_file = File.join(fixture_migrations_dir, "20240107000001_add_index_concurrently_to_users.rb")
  findings = analyzer.analyze_migration(migration_file)
  
  runner.assert_empty(findings, "Safe concurrent index should have no findings")
end

runner.test("does not flag safe column addition with default") do
  migration_file = File.join(fixture_migrations_dir, "20240108000001_add_default_status_to_users.rb")
  findings = analyzer.analyze_migration(migration_file)
  
  runner.assert_empty(findings, "Safe column with default should have no findings")
end

runner.test("returns empty array for non-existent file") do
  findings = analyzer.analyze_migration("/nonexistent/path/migration.rb")
  runner.assert_empty(findings)
end

runner.test("includes file_path in findings") do
  migration_file = File.join(fixture_migrations_dir, "20240101000001_create_users_table.rb")
  findings = analyzer.analyze_migration(migration_file)
  
  runner.assert_not_empty(findings)
  findings.each do |finding|
    runner.assert_equal(finding.file_path, migration_file)
  end
end

runner.test("includes line numbers in findings") do
 migration_file = File.join(fixture_migrations_dir, "20240101000001_create_users_table.rb")
  findings = analyzer.analyze_migration(migration_file)
  
  runner.assert_not_empty(findings)
  findings.each do |finding|
    runner.assert_true(finding.line_number > 0)
  end
end

runner.test("includes recommendations in findings") do
  migration_file = File.join(fixture_migrations_dir, "20240101000001_create_users_table.rb")
  findings = analyzer.analyze_migration(migration_file)
  
  runner.assert_not_empty(findings)
  findings.each do |finding|
    runner.assert_not_empty(finding.recommendations)
    runner.assert_true(finding.recommendations.first.is_a?(String))
  end
end

runner.test("includes metadata in findings") do
  migration_file = File.join(fixture_migrations_dir, "20240101000001_create_users_table.rb")
  findings = analyzer.analyze_migration(migration_file)
  
  runner.assert_not_empty(findings)
  findings.each do |finding|
    runner.assert_true(finding.metadata.is_a?(Hash))
  end
end

puts "\n#analyze_migrations_directory"

runner.test("scans all migrations in directory") do
  findings = analyzer.analyze_migrations_directory(fixture_migrations_dir)
  
  # Should find multiple findings across all migrations
  runner.assert_not_empty(findings, "Should find multiple findings")
  runner.assert_equal(findings.count > 5, true, "Should find at least 6 findings total")
end

runner.test("returns empty array for non-existent directory") do
  findings = analyzer.analyze_migrations_directory("/nonexistent/migrations")
  runner.assert_empty(findings)
end

runner.test("includes analyzer name in findings") do
  findings = analyzer.analyze_migrations_directory(fixture_migrations_dir)
  
  runner.assert_not_empty(findings)
  findings.each do |finding|
    runner.assert_equal(finding.analyzer_name, :migration_risk)
  end
end

puts "\n#analyze for registry integration"

runner.test("analyze method returns findings") do
  context = nil  # Migrations don't use context
  config = QueryGuard::Config.new
  config.migrations_directory = fixture_migrations_dir
  
  findings = analyzer.analyze(context, config)
  runner.assert_not_empty(findings, "Should find findings from directory")
end

success = runner.summary
exit(success ? 0 : 1)
