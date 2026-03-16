#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual test runner for table-size-aware migration analysis
$LOAD_PATH.unshift File.expand_path('lib', __dir__)

require 'query_guard'
require 'query_guard/migrations/migration_risk_detectors'
require 'query_guard/migrations/migration_analyzer'
require 'query_guard/migrations/database_adapter'
require 'query_guard/migrations/postgresql_adapter'
require 'query_guard/migrations/table_size_resolver'
require 'query_guard/migrations/table_risk_analyzer'

class SimpleDouble
  def initialize(name)
    @name = name
    @expectations = {}
    @call_count = {}
  end

  def method_missing(method, *args)
    if @expectations[method]
      @call_count[method] ||= 0
      @call_count[method] += 1
      @expectations[method].call(*args)
    else
      raise "No expectation set for #{method}"
    end
  end

  def expect(method)
    @expectations[method] = yield
    self
  end

  def call_count(method)
    @call_count[method] || 0
  end
end

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
    rescue => e
      @failed_tests += 1
      puts "  ✗ #{description} (Exception: #{e.class})"
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

  def assert_false(value, message = "")
    if value
      raise AssertionError, "Expected #{value.inspect} to be false. #{message}"
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

puts "Running Table-Size-Aware Migration Analysis Tests"
puts "=" * 60

puts "\nTableSizeResolver"

runner.test("extracts tables from add_column") do
  migration = "add_column :users, :name, :string"
  tables = QueryGuard::Migrations::TableSizeResolver.extract_table_names(migration)
  runner.assert_includes(tables, "users")
end

runner.test("extracts tables from remove_column") do
  migration = "remove_column :posts, :old_field"
  tables = QueryGuard::Migrations::TableSizeResolver.extract_table_names(migration)
  runner.assert_includes(tables, "posts")
end

runner.test("extracts tables from change_column") do
  migration = "change_column :users, :email, :text"
  tables = QueryGuard::Migrations::TableSizeResolver.extract_table_names(migration)
  runner.assert_includes(tables, "users")
end

runner.test("extracts tables from create_table") do
  migration = "create_table :accounts do |t|\n  t.string :name\nend"
  tables = QueryGuard::Migrations::TableSizeResolver.extract_table_names(migration)
  runner.assert_includes(tables, "accounts")
end

runner.test("extracts tables from add_index") do
  migration = "add_index :users, :email"
  tables = QueryGuard::Migrations::TableSizeResolver.extract_table_names(migration)
  runner.assert_includes(tables, "users")
end

runner.test("extracts tables from Model.update_all") do
  migration = "User.update_all(status: 'active')"
  tables = QueryGuard::Migrations::TableSizeResolver.extract_table_names(migration)
  runner.assert_includes(tables, "users")
end

runner.test("extracts tables from raw SQL UPDATE") do
  migration = "execute(\"UPDATE users SET status = 'active'\")"
  tables = QueryGuard::Migrations::TableSizeResolver.extract_table_names(migration)
  runner.assert_includes(tables, "users")
end

runner.test("deduplicates table names") do
  migration = "add_column :users, :name, :string\nadd_column :users, :email, :string"
  tables = QueryGuard::Migrations::TableSizeResolver.extract_table_names(migration)
  runner.assert_equal(tables.count, 1)
  runner.assert_equal(tables.first, "users")
end

runner.test("filters schema migrations table") do
  tables = ["users", "posts", "schema_migrations"]
  filtered = QueryGuard::Migrations::TableSizeResolver.filter_schema_tables(tables)
  runner.assert_includes(filtered, "users")
  runner.assert_includes(filtered, "posts")
  runner.assert_false(filtered.include?("schema_migrations"))
end

runner.test("returns empty for internal tables only") do
  migration = "execute(\"UPDATE ar_internal_metadata SET value = 'test'\")"
  tables = QueryGuard::Migrations::TableSizeResolver.affected_tables(migration)
  runner.assert_empty(tables)
end

puts "\nNullDatabaseAdapter"

adapter = QueryGuard::Migrations::NullDatabaseAdapter.new

runner.test("returns nil for estimate_table_rows") do
  runner.assert_equal(adapter.estimate_table_rows(:users), nil)
end

runner.test("returns nil for estimate_lock_risk") do
  runner.assert_equal(adapter.estimate_lock_risk(:users), nil)
end

runner.test("returns false for table_exists?") do
  runner.assert_false(adapter.table_exists?(:users))
end

runner.test("returns empty array for list_tables") do
  runner.assert_empty(adapter.list_tables)
end

runner.test("returns false for connected?") do
  runner.assert_false(adapter.connected?)
end

puts "\nTableRiskAnalyzer with NullDatabaseAdapter"

analyzer = QueryGuard::Migrations::TableRiskAnalyzer.new

runner.test("works gracefully without database connection") do
  migration = "add_index :users, :email"
  original_risk = {
    type: :index_not_concurrent,
    severity: :error,
    line_number: 1,
    migration_name: "test",
    title: "Test",
    description: "Test",
    message: "test",
    recommendation: "test",
    metadata: { operation: "add_index" }
  }
  
  enhanced = analyzer.enhance_risks(migration, [original_risk])
  runner.assert_equal(enhanced.length, 1)
  runner.assert_equal(enhanced.first[:severity], :error)
end

puts "\nTableRiskAnalyzer with Mock Adapter"

mock_adapter = SimpleDouble.new("MockAdapter")
mock_analyzer = QueryGuard::Migrations::TableRiskAnalyzer.new(mock_adapter)

runner.test("adds table metadata when adapter connected") do
  migration = "add_index :users, :email"
  original_risk = {
    type: :index_not_concurrent,
    severity: :error,
    line_number: 1,
    migration_name: "test",
    title: "Test",
    description: "Test",
    message: "test",
    recommendation: "test",
    metadata: { operation: "add_index" }
  }
  
  # Mock the adapter to return connected and table data
  mock_adapter.instance_eval do
    define_singleton_method(:connected?) { true }
    define_singleton_method(:estimate_table_rows) do |table|
      table == "users" ? 1_000_000 : nil
    end
    define_singleton_method(:estimate_lock_risk) do |table|
      table == "users" ? :medium : nil
    end
  end
  
  enhanced = mock_analyzer.enhance_risks(migration, [original_risk])
  runner.assert_equal(enhanced.first[:metadata][:table_name], "users")
  runner.assert_equal(enhanced.first[:metadata][:estimated_table_rows], 1_000_000)
  runner.assert_equal(enhanced.first[:metadata][:table_lock_risk], :medium)
end

runner.test("escalates severity for large tables") do
  migration = "add_index :users, :email"
  original_risk = {
    type: :index_not_concurrent,
    severity: :error,
    line_number: 1,
    migration_name: "test",
    title: "Test",
    description: "Test",
    message: "test",
    recommendation: "test",
    metadata: { operation: "add_index" }
  }
  
  # Mock adapter for large table
  mock_adapter.instance_eval do
    define_singleton_method(:connected?) { true }
    define_singleton_method(:estimate_table_rows) do |table|
      table == "users" ? 50_000_000 : nil
    end
    define_singleton_method(:estimate_lock_risk) do |table|
      table == "users" ? :high : nil
    end
  end
  
  enhanced = mock_analyzer.enhance_risks(migration, [original_risk])
  runner.assert_equal(enhanced.first[:severity], :critical)
  runner.assert_true(enhanced.first[:metadata][:severity_escalated])
end

runner.test("escalates WARN to ERROR for medium tables") do
  migration = "rename_column :users, :old_name, :new_name"
  original_risk = {
    type: :rename_column_lock,
    severity: :warn,
    line_number: 1,
    migration_name: "test",
    title: "Test",
    description: "Test",
    message: "test",
    recommendation: "test",
    metadata: { operation: "rename_column" }
  }
  
  # Mock adapter
  mock_adapter.instance_eval do
    define_singleton_method(:connected?) { true }
    define_singleton_method(:estimate_table_rows) do |table|
      table == "users" ? 5_000_000 : nil
    end
    define_singleton_method(:estimate_lock_risk) do |table|
      table == "users" ? :medium : nil
    end
  end
  
  enhanced = mock_analyzer.enhance_risks(migration, [original_risk])
  runner.assert_equal(enhanced.first[:severity], :error)
  runner.assert_false(enhanced.first[:severity] == :warn)
end

puts "\nIntegration Tests"

runner.test("MigrationAnalyzer with table size awareness") do
  # Use real analyzer with null adapter
  real_analyzer = QueryGuard::Migrations::MigrationAnalyzer.new
  migration_file = File.expand_path("spec/migrations/fixture_migrations/20240101000001_create_users_table.rb", __dir__)
  
  findings = real_analyzer.analyze_migration(migration_file)
  runner.assert_not_empty(findings)
  
  # Should have detected unsafe indexes
  unsafe_indexes = findings.select { |f| f.rule_name == :index_not_concurrent }
  runner.assert_equal(unsafe_indexes.count, 2)
end

runner.test("MigrationAnalyzer preserves findings without adapter") do
  analyzer_no_adapter = QueryGuard::Migrations::MigrationAnalyzer.new
  migration_file = File.expand_path("spec/migrations/fixture_migrations/20240105000001_migrate_old_data.rb", __dir__)
  
  findings = analyzer_no_adapter.analyze_migration(migration_file)
  runner.assert_not_empty(findings)
  
  # Should still detect dangerous SQL
  dangerous = findings.select { |f| f.rule_name == :dangerous_raw_sql }
  runner.assert_not_empty(dangerous)
end

success = runner.summary
exit(success ? 0 : 1)
