#!/usr/bin/env ruby
# frozen_string_literal: true

# Demonstration of improved QueryGuard CLI output
# Shows grouping, recommendations, index suggestions, migration steps, and summaries

$LOAD_PATH.unshift File.expand_path('lib', __dir__)

require 'query_guard/cli/formatter'

# Demo findings with various features
demo_findings = [
  # Migration risk - unsafe index addition
  {
    title: "Index Addition Without CONCURRENTLY",
    analyzer_name: :migration_risk,
    rule_name: :index_not_concurrent,
    severity: :error,
    file_path: "db/migrate/20240315_add_users_email_index.rb",
    line_number: 8,
    description: "Adding an index locks the table. Use algorithm: :concurrently for PostgreSQL.",
    recommendation: "Add algorithm: :concurrently to allow concurrent queries during index creation",
    metadata: {
      operation: "add_index",
      table_name: "users",
      estimated_table_rows: 5_000_000,
      risk_level: :high,
      index_sql: "add_index :users, :email, algorithm: :concurrently",
      safe_rollout_strategy: "Deploy during off-peak hours with monitoring"
    }
  },

  # Migration risk - column removal
  {
    title: "Remove Column Locks Table",
    analyzer_name: :migration_risk,
    rule_name: :remove_column_lock,
    severity: :error,
    file_path: "db/migrate/20240315_cleanup_legacy_fields.rb",
    line_number: 5,
    description: "Removing a column rewrites the entire table, causing extended lock and potential downtime.",
    recommendation: "Use safe column removal strategy",
    metadata: {
      operation: "remove_column",
      table_name: "users",
      estimated_table_rows: 5_000_000,
      migration_steps: [
        "Ensure application no longer uses the column (deploy app change first)",
        "Add column alias in migration helper for backward compatibility",
        "Run migration to drop the column",
        "Monitor database performance and replication lag"
      ]
    }
  },

  # Migration risk - non-nullable column without default
  {
    title: "Non-NULL Column Without Default",
    analyzer_name: :migration_risk,
    rule_name: :non_null_no_default,
    severity: :error,
    file_path: "db/migrate/20240315_cleanup_legacy_fields.rb",
    line_number: 12,
    description: "Adding a NOT NULL column without a default value will fail on populated tables.",
    recommendation: "Provide a default value, or add the column as nullable and backfill separately",
    metadata: {
      operation: "add_column",
      table_name: "subscriptions",
      estimated_table_rows: 2_500_000,
      migration_steps: [
        "Create the column with null: true (allow nulls for now)",
        "Add default or backfill values in background job",
        "Add NOT NULL constraint in separate migration",
        "Verify all rows have values before constraint"
      ]
    }
  },

  # Migration risk - table lock
  {
    title: "Rename Column Brief Lock",
    analyzer_name: :migration_risk,
    rule_name: :rename_column_lock,
    severity: :warn,
    file_path: "db/migrate/20240315_rename_legacy_fields.rb",
    line_number: 3,
    description: "Renaming a column briefly locks the table during metadata update.",
    recommendation: "Use with caution in large tables; consider aliasing in application code instead",
    metadata: {
      operation: "rename_column",
      table_name: "users",
      estimated_table_rows: 5_000_000
    }
  },

  # Query risk - select star
  {
    title: "SELECT * Usage Detected",
    analyzer_name: :query_risk,
    rule_name: :select_star,
    severity: :warn,
    file_path: "app/models/user.rb",
    line_number: 42,
    description: "Selecting all columns can fetch unnecessary data and reduce efficiency.",
    recommendation: "Specify only required columns explicitly for better performance",
    metadata: {
      table_name: "users",
      estimated_table_rows: 5_000_000
    }
  },

  # Query risk - LIKE without index
  {
    title: "LIKE Query Without Index",
    analyzer_name: :query_risk,
    rule_name: :like_without_index,
    severity: :warn,
    file_path: "app/models/product.rb",
    line_number: 28,
    description: "LIKE pattern matching typically requires full table scans unless you have a specialized index.",
    recommendation: "Consider adding a GiST or trigram index for LIKE queries",
    metadata: {
      table_name: "products",
      estimated_table_rows: 10_000_000,
      suggested_indexes: [
        "CREATE INDEX idx_products_name_trgm ON products USING GiST(name gist_trgm_ops);",
        "CREATE INDEX idx_products_name_like ON products(name varchar_pattern_ops);"
      ]
    }
  },

  # Query risk - N+1 pattern
  {
    title: "Potential N+1 Query Problem",
    analyzer_name: :query_risk,
    rule_name: :potential_n_plus_one,
    severity: :error,
    file_path: "app/controllers/posts_controller.rb",
    line_number: 15,
    description: "Many sequential queries in a single request indicates a potential N+1 problem.",
    recommendation: "Use eager loading with includes(:association) or includes(:assoc1, :assoc2)",
    metadata: {
      severity_escalated: true,
      original_severity: :warn,
      escalation_reason: "Large result set (10K+ queries detected)",
      risk_level: :critical,
      migration_steps: [
        "Use: Post.includes(:author, :comments).find_each",
        "Or use: @posts = Post.eager_load(:author).where(...)",
        "Add N+1 detection gem to CI/CD pipeline"
      ]
    }
  }
]

puts "\n" + "=" * 70
puts "QueryGuard CLI - Improved Output Demonstration"
puts "=" * 70

puts "\n📊 TEXT OUTPUT (Default):"
puts "-" * 70

formatter_text = QueryGuard::CLI::Formatter.new
formatter_text.print_text(demo_findings, "Migration & Query Safety Analysis")

puts "\n\n" + "=" * 70
puts "📊 JSON OUTPUT (For Automation):"
puts "-" * 70

formatter_json = QueryGuard::CLI::Formatter.new(json: true)
formatter_json.print_findings(demo_findings, "Migration & Query Safety Analysis")

puts "\n\n" + "=" * 70
puts "📊 VERBOSE OUTPUT (Debug Mode):"
puts "-" * 70

formatter_verbose = QueryGuard::CLI::Formatter.new(verbose: true)
# Show just first couple findings verbose
formatter_verbose.print_text(demo_findings.slice(0, 2), "Selected Findings (Verbose)")

puts "\n✅ Demonstration Complete!"
puts "\nKey Features Demonstrated:"
puts "  ✓ Grouping by severity (ERROR, WARN)"
puts "  ✓ Grouping by type (migration_risk, query_risk)"
puts "  ✓ File locations with line numbers"
puts "  ✓ Descriptions and recommendations"
puts "  ✓ Table context with row counts"
puts "  ✓ Index suggestions with SQL"
puts "  ✓ Migration steps as checklists"
puts "  ✓ Safe rollout strategies"
puts "  ✓ Severity escalation reasons"
puts "  ✓ Detailed summary with counts"
puts "  ✓ JSON output for CI/CD pipelines"
puts "  ✓ Verbose debug mode"
puts "\n"
