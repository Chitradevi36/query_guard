# PostgreSQL EXPLAIN Integration Quick Start

## 5-Minute Setup

### 1. Enable in Configuration
```ruby
# config/initializers/query_guard.rb
QueryGuard.configure do |config|
  config.analyze_query_risks = true
  config.use_explain_plans = true
  
  # Setup PostgreSQL EXPLAIN
  config.setup_postgresql_explain(ActiveRecord::Base.connection)
end

QueryGuard.install!
```

### 2. That's it! 

Query risk findings now include:
- ✅ Sequential scans (index opportunities)
- ✅ Nested loop joins (optimization potential)
- ✅ Estimate inaccuracies (stats issues)
- ✅ High query costs
- ✅ Expensive sorts
- ✅ Bitmap scans

## Example Findings

When a risky query is executed:

```ruby
# Result:
# [
#   {
#     analyzer_name: :query_risk,
#     rule_name: :sequential_scan_via_explain,
#     severity: :error,
#     title: "Sequential Table Scan Detected",
#     message: "Query uses sequential scan on users table (1000 estimated rows)",
#     sql: "SELECT * FROM users WHERE status = 'active'",
#     recommendations: [
#       "Consider adding an index to support query predicates",
#       "Add index on frequently filtered columns",
#       "Run ANALYZE to update table statistics"
#     ]
#   }
# ]
```

## Query Examples

### ✅ Will be analyzed:
- `SELECT * FROM users WHERE email = 'test@example.com'`
- `SELECT COUNT(*) FROM orders WHERE status = 'pending'`
- `WITH ranked AS (SELECT ...) SELECT * FROM ranked`
- `UPDATE users SET active = true WHERE created_at < '2020-01-01'`

### ❌ Will be rejected:
- `CREATE TABLE users (...)`
- `DROP TABLE users`
- `ALTER TABLE users ADD COLUMN age INT`
- `DELETE FROM users WHERE id = 1`
- `BEGIN; SELECT * FROM users; COMMIT;`

## Advanced Configuration

### Custom Timeout
```ruby
config.setup_postgresql_explain(
  connection,
  timeout: 10.0  # Default 5 seconds
)
```

### Enable ANALYZE (slower but more accurate)
```ruby
config.setup_postgresql_explain(
  connection,
  use_analyze: true  # Default false (safer)
)
```

### With Logging
```ruby
config.setup_postgresql_explain(
  connection,
  logger: Rails.logger
)
```

## Troubleshooting

### EXPLAIN queries seem slow
- Uses 5 second timeout by default
- Only runs on SELECT and safe queries
- Can disable: `config.use_explain_plans = false`

### No EXPLAIN signals appearing
Check:
1. `config.analyze_query_risks = true`
2. `config.use_explain_plans = true`
3. PostgreSQL connection available
4. Query is SELECT (not CREATE, DROP, etc.)

### Connection errors
```ruby
# Validate connection:
adapter = QueryGuard::Explain::PostgreSQLAdapter.new(
  connection,
  validate_connection: true  # Checks on init
)
# If this fails, something is wrong with DB connection
```

## Signal Severity Reference

| Signal | Severity | Action |
|--------|----------|--------|
| Sequential Scan | 🔴 ERROR | Add index |
| Missing Index | 🔴 ERROR | Analyze columns |
| High Cost | 🟡 WARN | Review query |
| Nested Loop Join | 🟡 WARN | Check indexes |
| Estimate Off | 🟡 WARN | Run ANALYZE |
| Expensive Sort | 🟡 WARN | Use pagination |
| High Planning Time | ⚪ INFO | Check complexity |
| Bitmap Scan | ⚪ INFO | Verify index |

## What Gets Detected

### Sequential Scans
```
Finds: Table scanned row-by-row
Suggests: Add index on filtered columns
```

### Missing Indexes
```
Finds: WHERE filter without index
Suggests: Create index on condition columns
```

### Join Performance
```
Finds: Nested loop joins (inner loops)
Suggests: Add indexes on join keys
```

### Query Complexity
```
Finds: High estimated cost, long planning time
Suggests: Simplify query, update statistics
```

### Estimate Problems
```
Finds: Planner estimates far from actual rows
Suggests: Run ANALYZE to update table stats
```

## Common Improvements

These findings help catch and fix:
1. **Index gaps**: Columns used in WHERE but not indexed
2. **Join inefficiency**: Missing indexes on join conditions
3. **Stale statistics**: ANALYZE is out of date
4. **Query complexity**: Expensive nested operations
5. **Memory issues**: Sorts and aggregations on large sets

## CLI/API Integration

```ruby
# Direct usage (outside Rails)
require 'query_guard'

adapter = QueryGuard::Explain::PostgreSQLAdapter.new(connection)
plan = adapter.get_plan("SELECT * FROM users WHERE status = 'active'")

enricher = QueryGuard::Explain::ExplainEnricher.new(adapter)
findings = enricher.enrich([], query)
findings.each { |f| puts "#{f.title}: #{f.recommendations.first}" }
```

## Performance Impact

- ✅ EXPLAIN without ANALYZE: 1-10ms overhead
- ✅ No actual queries executed  
- ✅ 5 second timeout prevents hanging
- ✅ Gracefully skipped if DB unavailable

Safe for production development environments.

## Next Steps

1. Enable in development/staging
2. Fix reported index issues
3. Update statistics with ANALYZE
4. Monitor performance improvements
5. Consider enabling for production insights

For questions or issues, check the logs:
```ruby
# Enable debug logging
config.setup_postgresql_explain(
  connection,
  logger: Rails.logger  # Set to DEBUG level
)
```

Logs will show EXPLAIN queries and any parsing/connection issues.
