# Table-Size-Aware Migration Risk Analysis

## Overview

The table-size-aware risk analysis feature extends QueryGuard's migration risk detection with intelligent severity escalation based on actual table sizes. When database metadata is available, QueryGuard can inform developers that certain operations are riskier on large tables that will experience longer locks.

**Key Benefits:**
- ⚠️ Escalates severity for operations on large tables (10M+ rows)
- 🔄 Graceful fallback to static analysis when database unavailable
- 🔌 Clean adapter pattern - pluggable database implementations
- ✅ Fully backwards compatible - adapter is optional

## Core Concept

Some database operations have different risk profiles depending on table size:

```
add_index on 100K rows          → :error (brief lock)
add_index on 50M rows           → :critical (lock for 10+ minutes!)
rename_column on 1M rows        → escalates :warn to :error
```

## Architecture

### Components

#### 1. DatabaseAdapter Interface
**File:** `lib/query_guard/migrations/database_adapter.rb`

Abstract interface defining how to query database metadata:

```ruby
module QueryGuard::Migrations
  class DatabaseAdapter
    def estimate_table_rows(table_name)      # → Integer or nil
    def estimate_lock_risk(table_name)       # → :low, :medium, :high, :critical
    def table_exists?(table_name)            # → Boolean
    def list_tables                          # → Array<String>
    def connected?                           # → Boolean
  end
end
```

**Built-in Adapters:**
- `NullDatabaseAdapter` - No-op implementation for graceful fallback
- `PostgreSQLAdapter` - Production implementation querying pg_class

#### 2. TableSizeResolver
**File:** `lib/query_guard/migrations/table_size_resolver.rb`

Extracts table names from migration code. Detects:
- Direct operations: `add_column`, `remove_column`, `change_column`, `create_table`, `add_index`, `drop_table`, `rename_column`
- Model operations: `User.update_all`, `Post.delete_all`
- Raw SQL: `UPDATE`, `DELETE`, `INSERT` statements
- Quote variants: `:users`, `"users"`, `'users'`

```ruby
migration = "add_column :users, :name, :string"
TableSizeResolver.extract_table_names(migration)
# => ["users"]

TableSizeResolver.affected_tables(migration)  # Filters out internal Rails tables
# => ["users"]
```

#### 3. TableRiskAnalyzer
**File:** `lib/query_guard/migrations/table_risk_analyzer.rb`

Escalates risk severity based on table size:

```ruby
adapter = PostgreSQLAdapter.new(connection: ActiveRecord::Base.connection)
analyzer = TableRiskAnalyzer.new(adapter)

risks = [
  {
    type: :index_not_concurrent,
    severity: :error,
    metadata: { operation: "add_index" }
  }
]

enhanced_risks = analyzer.enhance_risks(migration_content, risks)
# If table has 50M rows: severity escalated from :error to :critical
```

**Escalation Rules:**

| Table Size | Lock Risk | WARN Escalates To | ERROR Escalates To |
|---|---|---|---|
| < 1M rows | :low | (no change) | (no change) |
| 1M-10M rows | :medium | :error | :critical |
| 10M-100M rows | :high | :error | :critical |
| > 100M rows | :critical | :error | :critical |

#### 4. PostgreSQLAdapter
**File:** `lib/query_guard/migrations/postgresql_adapter.rb`

Production implementation for PostgreSQL. Uses `pg_class.reltuples` for fast row count estimation without table scans.

```ruby
adapter = QueryGuard::Migrations::PostgreSQLAdapter.new(
  connection: ActiveRecord::Base.connection,
  schema: 'public',            # Optional, default: 'public'
  enable_cache: true          # Optional, default: true
)

adapter.connected?                    # => true
adapter.estimate_table_rows('users')  # => 5_000_000
adapter.estimate_lock_risk('users')   # => :medium
adapter.clear_cache                   # Reset cached estimates
```

#### 5. MigrationAnalyzer Integration
**File:** `lib/query_guard/migrations/migration_analyzer.rb`

Updated to optionally accept and use database adapter:

```ruby
# Without adapter (static analysis only)
analyzer = MigrationAnalyzer.new
findings = analyzer.analyze_migration(file)

# With adapter (table-size aware)
adapter = PostgreSQLAdapter.new(connection: connection)
analyzer = MigrationAnalyzer.new(database_adapter: adapter)
findings = analyzer.analyze_migration(file)
```

## Usage

### Basic Usage

```ruby
require 'query_guard'

# Initialize analyzer with database awareness
adapter = QueryGuard::Migrations::PostgreSQLAdapter.new(
  connection: ActiveRecord::Base.connection
)
analyzer = QueryGuard::Migrations::MigrationAnalyzer.new(
  database_adapter: adapter
)

# Analyze migration
file_path = 'db/migrate/20240115_add_user_index.rb'
findings = analyzer.analyze_migration(file_path)

# Enhanced findings include table metadata and escalated severity
findings.each do |finding|
  if finding[:metadata][:severity_escalated]
    puts "⚠️  #{finding[:title]}"
    puts "   Table: #{finding[:metadata][:table_name]}"
    puts "   Rows: #{finding[:metadata][:estimated_table_rows]}"
    puts "   Reason: #{finding[:metadata][:escalation_reason]}"
  end
end
```

### With Graceful Fallback

```ruby
# Works without database - falls back to static analysis
if production_environment?
  adapter = PostgreSQLAdapter.new(connection: db_connection)
else
  adapter = NullDatabaseAdapter.new  # Or omit entirely
end

analyzer = MigrationAnalyzer.new(database_adapter: adapter)
findings = analyzer.analyze_migration(file)
# If adapter not connected, uses static risk levels
```

### Custom Database Adapter

```ruby
class CustomDatabaseAdapter < DatabaseAdapter
  def initialize(client)
    @client = client
  end

  def connected?
    @client.ping
  end

  def estimate_table_rows(table_name)
    @client.query("SELECT COUNT(*) FROM #{table_name}").first
  end

  def estimate_lock_risk(table_name)
    rows = estimate_table_rows(table_name)
    case rows
    when 0...1_000_000         then :low
    when 1_000_000...10_000_000 then :medium
    when 10_000_000...100_000_000 then :high
    else                           :critical
    end
  end

  def table_exists?(table_name)
    @client.table_exists?(table_name)
  end

  def list_tables
    @client.tables
  end
end

# Use custom adapter
adapter = CustomDatabaseAdapter.new(client)
analyzer = MigrationAnalyzer.new(database_adapter: adapter)
```

## Risk Escalation Examples

### Example 1: Adding Index on Large Table

```ruby
# Migration
class AddUserEmailIndex < ActiveRecord::Migration[6.0]
  def change
    add_index :users, :email  # Table has 50M rows!
  end
end
```

**Static Analysis Result:**
```ruby
{
  type: :index_not_concurrent,
  severity: :error,
  # ... other fields
}
```

**With Table-Size Analysis:**
```ruby
{
  type: :index_not_concurrent,
  severity: :critical,  # ← Escalated!
  metadata: {
    table_name: "users",
    estimated_table_rows: 50_000_000,
    table_lock_risk: :high,
    severity_escalated: true,
    original_severity: :error,
    escalation_reason: "Large table (50.0M rows)"
  }
}
```

### Example 2: Renaming Column on Medium Table

```ruby
class RenameUserNameField < ActiveRecord::Migration[6.0]
  def change
    rename_column :users, :old_name, :new_name  # Table has 5M rows
  end
end
```

**Static Analysis:** `:warn` (renaming columns locks table)

**With Table-Size Analysis:** `:error` (medium table escalates warning to error)

### Example 3: Table Without Data (No Escalation)

```ruby
class CreateNewFeatureTable < ActiveRecord::Migration[6.0]
  def change
    create_table :new_features do |t|  # New, empty table
      t.string :name
      t.references :user
    end
  end
end
```

**Result:** No escalation - table is empty (0 rows = :low risk)

## Configuration

### PostgreSQLAdapter Options

```ruby
# Default configuration
adapter = QueryGuard::Migrations::PostgreSQLAdapter.new(
  connection: ActiveRecord::Base.connection,  # Required: AR connection
  schema: 'public',                           # Optional: schema to query
  enable_cache: true                          # Optional: cache results
)

# With different schema
adapter = PostgreSQLAdapter.new(
  connection: connection,
  schema: 'analytics'
)

# Without caching (always fresh data)
adapter = PostgreSQLAdapter.new(
  connection: connection,
  enable_cache: false
)
```

## Row Count Thresholds

The default thresholds for risk escalation are:

- **< 1M rows:** `:low` - No escalation, minimal lock time
- **1M-10M rows:** `:medium` - Escalate WARN→ERROR, operations will have noticeable lock periods
- **10M-100M rows:** `:high` - Escalate all warnings to ERROR/CRITICAL
- **> 100M rows:** `:critical` - Already at highest risk level

Example with 2M row table (medium risk):
```
:warn severity → escalated to :error
```

Example with 50M row table (high risk):
```
:warn severity → escalated to :error
:error severity → escalated to :critical
```

## Testing

### Test with Database Connection

```ruby
RSpec.describe "Migration Analysis with Table Awareness" do
  let(:adapter) do
    QueryGuard::Migrations::PostgreSQLAdapter.new(
      connection: ActiveRecord::Base.connection
    )
  end

  let(:analyzer) do
    QueryGuard::Migrations::MigrationAnalyzer.new(database_adapter: adapter)
  end

  it "escalates severity for large table operations" do
    migration = "add_index :users, :email"
    findings = analyzer.analyze_migration(migration)
    
    # Gets actual row count from database
    expect(findings.first[:severity]).to eq(:critical)
  end
end
```

### Test with Mock Adapter

```ruby
class MockDatabaseAdapter < QueryGuard::Migrations::DatabaseAdapter
  def initialize(table_sizes)
    @table_sizes = table_sizes
  end

  def connected?
    true
  end

  def estimate_table_rows(table_name)
    @table_sizes[table_name]
  end

  def estimate_lock_risk(table_name)
    rows = estimate_table_rows(table_name)
    case rows
    when 0...1_000_000         then :low
    when 1_000_000...10_000_000 then :medium
    else                           :high
    end
  end

  def table_exists?(table_name)
    @table_sizes.key?(table_name)
  end

  def list_tables
    @table_sizes.keys
  end
end

# Usage in tests
adapter = MockDatabaseAdapter.new(
  'users' => 50_000_000,
  'posts' => 100_000
)
analyzer = MigrationAnalyzer.new(database_adapter: adapter)
```

### Test without Database (Graceful Fallback)

```ruby
it "works without database connection" do
  # Use NullDatabaseAdapter for testing
  analyzer = MigrationAnalyzer.new(
    database_adapter: QueryGuard::Migrations::NullDatabaseAdapter.new
  )
  
  migration = "add_index :users, :email"
  findings = analyzer.analyze_migration(migration)
  
  # Falls back to static analysis
  expect(findings.first[:severity]).to eq(:error)
  expect(findings.first[:metadata][:severity_escalated]).to be false
end
```

## Performance Considerations

### Row Count Estimation

The PostgreSQL adapter uses `pg_class.reltuples`, which provides:
- ✅ Very fast (single system catalog query, no table scan)
- ✅ Accurate for large tables (VACUUM/ANALYZE updates it)
- ✅ Cached by default (configurable)
- ⚠️ May be stale if tables have frequent changes without ANALYZE

**Without caching:**
- Each analysis hits the database once per unique table
- Recommended for CI/CD with small number of tables

**With caching:**
- First analysis caches all row counts
- Subsequent analyses use cached estimates
- Call `.clear_cache()` to refresh

### Query Cost

For a migration affecting 3 tables with cache enabled:
- First call: 3 DB queries (one per table) + cached
- Subsequent calls: 0 DB queries (uses cache)
**Total Overhead:** < 5ms per migration analysis

## Limitations

1. **Model Name to Table Name Conversion:**
   - Uses simple snake_case conversion
   - Does not handle irregular plurals (Person→people, Box→boxes)
   - Works for standard Rails naming conventions (User→users, Post→posts)

2. **Row Count Accuracy:**
   - PostgreSQL `pg_class.reltuples` can be stale
   - Run `VACUUM ANALYZE` or `ANALYZE` to update statistics
   - Cannot detect if table will be large *after* migration

3. **Table Detection:**
   - Cannot analyze dynamic table creation from variables
   - Limited to standard Rails DSL and common SQL patterns
   - Raw SQL with string literals may not be detected

4. **Lock Time Estimation:**
   - Provides risk categories, not exact lock duration
   - Actual lock time depends on CPU, I/O, lock contention
   - Should pair with monitoring in actual deployments

## Edge Cases

### NULL Rows Detection
When row count cannot be estimated:
```ruby
adapter.estimate_table_rows('nonexistent') # => nil
# Risk is not escalated, static analysis severity applies
```

### Database Disconnected
```ruby
# Automatic fallback to NullDatabaseAdapter
adapter = PostgreSQLAdapter.new(connection: bad_connection)
adapter.connected?  # => false

analyzer = MigrationAnalyzer.new(database_adapter: adapter)
# Uses static analysis, no escalation occurs
```

### Mixed Operations
```ruby
migration = <<~RUBY
  def change
    add_column :users, :status, :string    # Large table
    create_table :audit_logs do |t|        # New table
      t.references :user
    end
  end
RUBY

# Returns multiple findings:
# 1. add_column: escalated (users has 50M rows)
# 2. create_table: not escalated (new table, 0 rows)
```

## Future Enhancements

Potential improvements for future versions:

- [ ] Support for MySQL, SQLite, Oracle database adapters
- [ ] Advanced pluralization (using Rails inflector)
- [ ] Lock time estimation based on CPU/I/O profiling
- [ ] Track migration history and correlate with performance incidents
- [ ] Integration with schema cache warmer
- [ ] Concurrent index creation recommendations
- [ ] Estimate safe downtime windows

## Troubleshooting

### "Database connection check failed"
**Cause:** PostgreSQLAdapter cannot connect to database

**Solution:**
```ruby
# Check connection
adapter = PostgreSQLAdapter.new(connection: connection)
puts adapter.connected?

# Use NullDatabaseAdapter as fallback
adapter ||= NullDatabaseAdapter.new
```

### Escalation not happening
**Cause:** Adapter not connected or table not detected

**Debug:**
```ruby
adapter = PostgreSQLAdapter.new(connection: connection)
puts "Connected: #{adapter.connected?}"

tables = TableSizeResolver.affected_tables(migration)
puts "Detected tables: #{tables}"

tables.each do |table|
  puts "Rows in #{table}: #{adapter.estimate_table_rows(table)}"
end
```

### Stale row counts
**Cause:** PostgreSQL statistics not updated

**Solution:**
```ruby
# Force statistics update
ActiveRecord::Base.connection.execute("ANALYZE")

# Clear adapter cache
adapter.clear_cache
```

## References

- [PostgreSQL System Catalog: pg_class](https://www.postgresql.org/docs/current/catalog-pg-class.html)
- [ActiveRecord Migration Reference](https://guides.rubyonrails.org/active_record_migrations.html)
- [Rails Lock Time Considerations](https://github.com/ankane/strong_migrations)

## License

Part of QueryGuard. See LICENSE.txt for details.
