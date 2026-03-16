#!/usr/bin/env ruby
# frozen_string_literal: true

# Tests for improved CLI formatter output
# Validates grouping, recommendations, and special metadata display

$LOAD_PATH.unshift File.expand_path('lib', __dir__)

require 'json'
require 'stringio'
require 'query_guard/cli/formatter'

class SimpleTestRunner
  attr_reader :passed, :failed, :tests

  def initialize
    @passed = 0
    @failed = 0
    @tests = []
  end

  def assert_equal(expected, actual, message)
    if expected == actual
      @passed += 1
      puts "  ✓ #{message}"
    else
      @failed += 1
      puts "  ✗ #{message}"
      puts "    Expected: #{expected.inspect}"
      puts "    Actual: #{actual.inspect}"
    end
    @tests << { message: message, passed: expected == actual }
  end

  def assert_true(value, message)
    if value
      @passed += 1
      puts "  ✓ #{message}"
    else
      @failed += 1
      puts "  ✗ #{message}"
    end
    @tests << { message: message, passed: value }
  end

  def assert_includes(haystack, needle, message)
    if haystack.include?(needle)
      @passed += 1
      puts "  ✓ #{message}"
    else
      @failed += 1
      puts "  ✗ #{message}"
      puts "    Expected to find: #{needle.inspect}"
      puts "    In: #{haystack.inspect}"
    end
    @tests << { message: message, passed: haystack.include?(needle) }
  end

  def summary
    puts "\n" + "=" * 60
    puts "Test Summary: #{@passed}/#{@passed + @failed} passed"
    puts "=" * 60 + "\n"
  end
end

# Helper to capture output
def capture_output
  old_stdout = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = old_stdout
end

# Helper to strip ANSI color codes
def strip_ansi(text)
  text.gsub(/\e\[[0-9;]*m/, '')
end

# Test data builder
def build_finding(attrs = {})
  defaults = {
    title: "Test Finding",
    analyzer_name: :test_analyzer,
    rule_name: :test_rule,
    severity: :warn,
    file_path: "db/migrate/001_create_users.rb",
    line_number: 10,
    description: "This is a test finding",
    recommendation: "Fix this issue",
    metadata: {}
  }
  defaults.merge(attrs)
end

# ============================================================
# FORMAT OUTPUT TESTS
# ============================================================

runner = SimpleTestRunner.new

puts "\n" + "=" * 60
puts "Formatter Output Format Tests"
puts "=" * 60

# TEST 1: Grouping by severity
puts "\nGrouping & Severity Tests"
puts "-" * 60

findings = [
  build_finding(severity: :error, title: "Error 1", rule_name: :rule_a),
  build_finding(severity: :error, title: "Error 2", rule_name: :rule_b),
  build_finding(severity: :warn, title: "Warning 1", rule_name: :rule_c),
  build_finding(severity: :info, title: "Info 1", rule_name: :rule_d)
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text(findings, "Test Analysis")
end

# Verify severity sections appear
runner.assert_includes(output, "❌", "ERROR icon displayed")
runner.assert_includes(output, "ERROR", "ERROR label displayed")
runner.assert_includes(output, "⚠️", "WARN icon displayed")
runner.assert_includes(output, "INFO", "INFO label displayed")

# Verify counts
runner.assert_includes(output, "ERROR (2)", "Error count displayed")
runner.assert_includes(output, "WARN (1)", "Warning count displayed")

# TEST 2: Type grouping within severity
puts "\nType Grouping Tests"
puts "-" * 60

findings_same_type = [
  build_finding(
    severity: :error,
    analyzer_name: :migration_risk,
    rule_name: :index_not_concurrent,
    title: "Index 1 Without CONCURRENTLY",
    line_number: 5
  ),
  build_finding(
    severity: :error,
    analyzer_name: :migration_risk,
    rule_name: :index_not_concurrent,
    title: "Index 2 Without CONCURRENTLY",
    line_number: 15
  )
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text(findings_same_type, "Migration Check")
end

runner.assert_includes(output, "[migration_risk:index_not_concurrent] (2 findings)", "Type groups same findings")

# TEST 3: File location display
puts "\nFile Location Display Tests"
puts "-" * 60

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text([findings[0]], "Location Test")
end

runner.assert_includes(output, "📄 db/migrate/001_create_users.rb:10", "File path with line number displayed")

# TEST 4: Recommendations display
puts "\nRecommendations Display Tests"
puts "-" * 60

findings_with_recs = [
  build_finding(
    recommendation: "Use algorithm: :concurrently for safe index creation",
    metadata: {}
  )
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text(findings_with_recs, "Recommendations Test")
end

runner.assert_includes(output, "✅ Recommended Actions:", "Recommendations section header")
runner.assert_includes(output, "Use algorithm: :concurrently", "Recommendation text displayed")

# TEST 5: Index suggestions display
puts "\nIndex Suggestions Tests"
puts "-" * 60

findings_with_index = [
  build_finding(
    metadata: {
      index_sql: "CREATE INDEX idx_users_email ON users(email);"
    }
  )
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text(findings_with_index, "Index Test")
end

runner.assert_includes(output, "🔧 Suggested Index:", "Index suggestion header")
runner.assert_includes(output, "CREATE INDEX idx_users_email", "Index SQL displayed")

# TEST 6: Multiple index suggestions
puts "\nMultiple Index Suggestions Tests"
puts "-" * 60

findings_with_indexes = [
  build_finding(
    metadata: {
      suggested_indexes: [
        "CREATE INDEX idx_users_email ON users(email);",
        "CREATE INDEX idx_users_status ON users(status);"
      ]
    }
  )
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text(findings_with_indexes, "Multiple Indexes Test")
end

runner.assert_includes(output, "🔧 Suggested Indexes:", "Multiple indexes header")
runner.assert_includes(output, "CREATE INDEX idx_users_email", "First index displayed")
runner.assert_includes(output, "CREATE INDEX idx_users_status", "Second index displayed")

# TEST 7: Migration steps display
puts "\nMigration Steps Tests"
puts "-" * 60

findings_with_steps = [
  build_finding(
    metadata: {
      migration_steps: [
        "Create new column with default",
        "Backfill existing rows",
        "Add NOT NULL constraint",
        "Drop old column"
      ]
    }
  )
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text(findings_with_steps, "Migration Steps Test")
end

runner.assert_includes(output, "📋 Migration Steps:", "Migration steps header")
runner.assert_includes(output, "1. Create new column", "First step numbered")
runner.assert_includes(output, "4. Drop old column", "Last step numbered")

# TEST 8: Safe rollout strategy display
puts "\nSafe Rollout Strategy Tests"
puts "-" * 60

findings_with_strategy = [
  build_finding(
    metadata: {
      safe_rollout_strategy: "Deploy index in off-peak hours with monitoring"
    }
  )
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text(findings_with_strategy, "Rollout Test")
end

runner.assert_includes(output, "🛡️  Safe Rollout Strategy:", "Strategy header")
runner.assert_includes(output, "Deploy index in off-peak hours", "Strategy text displayed")

# TEST 9: Table context display
puts "\nTable Context Display Tests"
puts "-" * 60

findings_with_table = [
  build_finding(
    metadata: {
      table_name: "users",
      estimated_table_rows: 5_000_000
    }
  )
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text(findings_with_table, "Table Context Test")
end

runner.assert_includes(output, "🗂️  Table: users", "Table name displayed")
runner.assert_includes(output, "5.0M rows", "Row count formatted and displayed")

# TEST 10: Operation context display
puts "\nOperation Context Display Tests"
puts "-" * 60

findings_with_operation = [
  build_finding(
    metadata: {
      operation: "remove_column"
    }
  )
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text(findings_with_operation, "Operation Test")
end

runner.assert_includes(output, "⚙️  Operation: remove_column", "Operation displayed")

# TEST 11: Severity escalation display
puts "\nSeverity Escalation Tests"
puts "-" * 60

findings_with_escalation = [
  build_finding(
    metadata: {
      severity_escalated: true,
      original_severity: :warn,
      escalation_reason: "Large table (5M rows)"
    }
  )
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text(findings_with_escalation, "Escalation Test")
end

runner.assert_includes(output, "⬆️  Escalated from warn:", "Escalation indicator")
runner.assert_includes(output, "Large table (5M rows)", "Escalation reason")

# TEST 12: Summary display
puts "\nSummary Output Tests"
puts "-" * 60

findings_summary = [
  build_finding(severity: :error, rule_name: :rule_a),
  build_finding(severity: :error, rule_name: :rule_b),
  build_finding(severity: :warn, rule_name: :rule_c),
  build_finding(severity: :warn, rule_name: :rule_d),
  build_finding(severity: :info, rule_name: :rule_e)
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text(findings_summary, "Summary Test")
end

runner.assert_includes(output, "SUMMARY", "Summary section header")
runner.assert_includes(output, "Total Findings: 5", "Total count in summary")
runner.assert_includes(output, "❌ ERROR: 2", "Error count in summary")
runner.assert_includes(output, "⚠️  WARN: 2", "Warn count in summary")
runner.assert_includes(output, "ℹ️  INFO: 1", "Info count in summary")

# TEST 13: No findings message
puts "\nNo Findings Tests"
puts "-" * 60

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text([], "Empty Test")
end

runner.assert_includes(output, "✅ No issues found!", "No findings message")

# TEST 14: Verbose mode metadata
puts "\nVerbose Mode Tests"
puts "-" * 60

findings_verbose = [
  build_finding(
    metadata: {
      custom_key: "custom_value",
      debug_info: "extra data"
    }
  )
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new(verbose: true)
  formatter.print_text(findings_verbose, "Verbose Test")
end

runner.assert_includes(output, "[Debug]", "Debug section shown in verbose mode")
runner.assert_includes(output, "custom_key", "Custom metadata shown in verbose")

# TEST 15: JSON output format
puts "\nJSON Output Tests"
puts "-" * 60

findings_json = [
  build_finding(
    analyzer_name: :migration_risk,
    rule_name: :index_not_concurrent,
    severity: :error,
    file_path: "db/migrate/001_test.rb",
    line_number: 5
  )
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new(json: true)
  formatter.print_findings(findings_json, "JSON Output Test")
end

begin
  json_data = JSON.parse(output)
  runner.assert_true(json_data.is_a?(Hash), "Output is valid JSON")
  runner.assert_true(json_data.key?("summary"), "JSON has summary section")
  runner.assert_true(json_data.key?("findings"), "JSON has findings section")
  runner.assert_equal(1, json_data["summary"]["total"], "JSON summary has correct total")
  runner.assert_equal("migration_risk:index_not_concurrent", json_data["findings"][0]["type"], "JSON finding type includes both names")
rescue JSON::ParserError => e
  runner.assert_true(false, "JSON parse error: #{e.message}")
end

# TEST 16: JSON metadata summary
puts "\nJSON Metadata Summary Tests"
puts "-" * 60

findings_with_all_features = [
  build_finding(
    metadata: {
      index_sql: "CREATE INDEX idx_test ON table(column);"
    }
  ),
  build_finding(
    metadata: {
      migration_steps: ["Step 1", "Step 2"]
    }
  )
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new(json: true)
  formatter.print_findings(findings_with_all_features, "JSON Metadata Test")
end

begin
  json_data = JSON.parse(output)
  runner.assert_true(json_data["metadata"]["has_index_suggestions"], "JSON metadata detects index suggestions")
  runner.assert_true(json_data["metadata"]["has_migration_steps"], "JSON metadata detects migration steps")
  runner.assert_equal(1, json_data["metadata"]["total_files"], "JSON metadata counts files")
rescue JSON::ParserError => e
  runner.assert_true(false, "JSON metadata parse error: #{e.message}")
end

# TEST 17: Multiple file locations in summary
puts "\nMultiple File Locations in Summary Tests"
puts "-" * 60

findings_multi_files = [
  build_finding(file_path: "db/migrate/001_test.rb"),
  build_finding(file_path: "db/migrate/002_test.rb"),
  build_finding(file_path: "db/migrate/002_test.rb"),
  build_finding(file_path: nil)
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text(findings_multi_files, "Multi File Test")
end

runner.assert_includes(output, "2 files with findings", "Multiple files counted correctly")

# TEST 18: Type detection with different analyzers
puts "\nType Detection Tests"
puts "-" * 60

findings_mixed_types = [
  build_finding(analyzer_name: :migration_risk, rule_name: :index_not_concurrent),
  build_finding(analyzer_name: :migration_risk, rule_name: :remove_column_lock),
  build_finding(analyzer_name: :query_risk, rule_name: :select_star)
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text(findings_mixed_types, "Type Detection Test")
end

runner.assert_includes(output, "[migration_risk:index_not_concurrent]", "Analyzer name in type")
runner.assert_includes(output, "[migration_risk:remove_column_lock]", "Rule name in type")
runner.assert_includes(output, "[query_risk:select_star]", "Query risk type shown")

# TEST 19: Indentation consistency
puts "\nIndentation Tests"
puts "-" * 60

findings_indent = [
  build_finding(severity: :error, title: "Test Issue")
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text(findings_indent, "Indent Test")
end

lines = output.split("\n")
finding_lines = lines.select { |line| line.include?("Test Issue") || line.include?("📄") }

runner.assert_true(finding_lines.any? { |line| line.start_with?("  ") }, "Finding lines are indented")

# TEST 20: Complex scenario with all features
puts "\nComplex Scenario Tests"
puts "-" * 60

complex_findings = [
  build_finding(
    severity: :error,
    analyzer_name: :migration_risk,
    rule_name: :index_not_concurrent,
    title: "Index Addition Without CONCURRENTLY",
    file_path: "db/migrate/20240101_add_users_email_index.rb",
    line_number: 8,
    description: "Adding an index locks the table. Use algorithm: :concurrently for PostgreSQL.",
    recommendation: "Add algorithm: :concurrently to allow concurrent queries",
    metadata: {
      operation: "add_index",
      table_name: "users",
      estimated_table_rows: 50_000_000,
      risk_level: :high,
      index_sql: "add_index :users, :email, algorithm: :concurrently",
      safe_rollout_strategy: "Deploy during off-peak hours (2-4 AM UTC)"
    }
  ),
  build_finding(
    severity: :warn,
    analyzer_name: :migration_risk,
    rule_name: :rename_column_lock,
    title: "Rename Column Brief Lock",
    file_path: "db/migrate/20240101_add_users_email_index.rb",
    line_number: 15,
    description: "Renaming a column briefly locks the table during metadata update.",
    recommendation: "Use with caution in large tables",
    metadata: {
      operation: "rename_column",
      table_name: "users",
      estimated_table_rows: 50_000_000,
      migration_steps: [
        "Deploy new column alias to application code",
        "Run migration to rename column",
        "Update application to use new name",
        "Remove old name from application"
      ]
    }
  )
]

output = capture_output do
  formatter = QueryGuard::CLI::Formatter.new
  formatter.print_text(complex_findings, "Production Migration Check")
end

runner.assert_includes(output, "ERROR (1)", "Complex scenario counts errors")
runner.assert_includes(output, "WARN (1)", "Complex scenario counts warnings")
runner.assert_includes(output, "Index Addition Without CONCURRENTLY", "Complex scenario shows title")
runner.assert_includes(output, "50.0M rows", "Complex scenario formats large row count")
runner.assert_includes(output, "algorithm: :concurrently", "Complex scenario shows index SQL")
runner.assert_includes(output, "2. Run migration to rename column", "Complex scenario shows migration steps")
runner.assert_includes(output, "Off-peak hours", "Complex scenario shows rollout strategy")
runner.assert_includes(output, "[migration_risk:rename_column_lock]", "Complex scenario groups by type")

# Summary
runner.summary
