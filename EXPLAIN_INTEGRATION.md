# PostgreSQL EXPLAIN Integration Guide for QueryGuard

## Overview

The EXPLAIN integration adds actual query plan analysis to QueryGuard's risk detection system. Instead of relying solely on heuristic pattern matching, you can now analyze real PostgreSQL query plans to detect:

- **Sequential scans** on tables that should have indexes
- **Missing indexes** suggested by actual execution plans
- **Estimate inaccuracies** (planner vs. reality)
- **High query costs** that indicate optimization opportunities

## Why EXPLAIN?

### Heuristics vs. Reality

**Phase 4 Heuristic Detection:**
- Pattern-based: "LIKE without index" is detected as risky
- Fast: <1ms per query
- Some false positives/negatives

**Phase 5 EXPLAIN Analysis:**
- Actual plan data: "Table scan on users_table"
- Accurate: Based on real database statistics
- Precise index detection and cost analysis
- Slower: ~5-50ms per query (actual plan execution)

### When to Use EXPLAIN

| Scenario | Use EXPLAIN? |
|----------|-------------|
| Development/testing only | Yes - get accurate feedback |
| Production trace sampling | Maybe - know the cost of EXPLAIN |
| Real-time request analysis | No - too slow for every query |
| Periodic query tuning | Yes - analyze slow queries separately |

## Setup

### Step 1: Ensure PostgreSQL Connection

You need access to an active database connection. This is automatic in Rails.

### Step 2: Configure EXPLAIN Support

```ruby
# config/initializers/query_guard.rb

QueryGuard.configure do |config|
  # Enable risk analysis (Phase 4)
  config.analyze_query_risks = true

  # Enable EXPLAIN enrichment (Phase 5)
  config.use_explain_plans = true
end

# Initialize EXPLAIN support after Rails initialization
# (when database connection is available)
Rails.application.config.after_initialize do
  if defined?(Rails) && QueryGuard.config.use_explain_plans
    success = QueryGuard.config.setup_postgresql_explain(
      ActiveRecord::Base.connection,
      timeout: 5.0,
      use_analyze: false  # WARNING: ANALYZE actually runs the query!
    )

    Rails.logger.warn "[QueryGuard] EXPLAIN setup failed" unless success
  end
end
```

### EXPLAIN Options

```ruby
QueryGuard.config.setup_postgresql_explain(
  connection,
  timeout: 10.0,           # Max seconds to wait for EXPLAIN
  use_analyze: false,      # Run actual query for real metrics (SLOWER!)
  logger: Rails.logger     # Custom logger
)
```

**WARNING:** `use_analyze: true` actually executes your queries! This is useful for:
- Development/testing environments
- Analyzing specific slow queries
- NOT recommended for production

Without ANALYZE, you get planner estimates only (faster, safe).

## How It Works

### Architecture Flow

```
Query executes
    ↓
Risk Analyzer detects patterns (Phase 4)
    ↓
[if use_explain_plans enabled]
    ↓
PostgreSQL Adapter
    ├─ Validates query is safe to EXPLAIN
    ├─ Executes: EXPLAIN (FORMAT JSON) <query>
    ├─ Parses plan into data structure
    └─ Returns QueryPlan object
    ↓
Query Plan Analyzer extracts signals
    ├─ Find sequential scans
    ├─ Detect missing indexes
    ├─ Check estimate accuracy
    └─ Calculate query costs
    ↓
Enricher converts signals → Finding objects
    ├─ Sequential scan → Error severity finding
    ├─ Missing index → Error severity finding
    ├─ Estimate inaccuracy → Warning severity finding
    └─ High cost → Warning severity finding
    ↓
Original findings + EXPLAIN findings returned
```

### Signal Types

**Sequential Scan Detection**
```json
{
  "type": "sequential_scan",
  "severity": "high",
  "table": "users",
  "estimated_rows": 1000,
  "message": "Sequential scan on users (1000 estimated rows)",
  "recommendation": "Consider adding an index"
}
```

**Missing Index Detection**
```json
{
  "type": "likely_missing_index",
  "severity": "high",
  "table": "orders",
  "filter": "(user_id = 123)",
  "message": "Sequential scan with filter on orders",
  "recommendation": "Analyze columns in filter condition"
}
```

**Estimate Inaccuracy**
```json
{
  "type": "estimate_inaccuracy",
  "severity": "medium",
  "node": "Seq Scan on users",
  "ratio": 15.5,
  "message": "Estimate off by 1550%: estimated 100, actual 1550",
  "recommendation": "Run ANALYZE to update statistics"
}
```

**High Query Cost**
```json
{
  "type": "high_estimated_cost",
  "severity": "medium",
  "cost": 25000.0,
  "message": "Query has estimated cost: 25000.0",
  "recommendation": "Review query structure and indexes"
}
```

## Usage Examples

### Basic Usage (Development)

```ruby
# In your Rails app, findings appear automatically:

# If run during request, all findings are collected:
QueryGuard findings:
  - SELECT * Usage (heuristic)
  - Sequential Table Scan Detected (EXPLAIN)
  - Missing Index Detected (EXPLAIN)
  - Query Plan Estimate Inaccuracy (EXPLAIN)
```

### Analyzing Specific Slow Queries

```ruby
# Manually analyze a query with EXPLAIN:

adapter = QueryGuard::Explain::PostgreSQLAdapter.new(
  ActiveRecord::Base.connection,
  use_analyze: true  # Actually run the query
)

sql = "SELECT o.*, u.* FROM orders o JOIN users u ON o.user_id = u.id"
plan = adapter.get_plan(sql)

# plan is a structured Hash with:
plan["Plan"]["Node Type"]          # "Hash Join"
plan["Plan"]["Relation Name"]      # "orders"
plan["Plan"]["Total Cost"]         # 150.42
plan["Plan"]["Actual Rows"]        # (only with use_analyze: true)
plan["Execution Time"]             # ms

# Extract signals from plan:
query_plan = QueryGuard::Explain::PlanSignals::QueryPlan.new(plan)
signals = QueryGuard::Explain::PlanSignals::PlanSignals.new(query_plan)

signals.to_a.each do |sig|
  puts "#{sig[:type]}: #{sig[:message]}"
end
```

### Custom Adapter for MySQL/Others

```ruby
# Create your own adapter:

class MySQLAdapter < QueryGuard::Explain::AdapterInterface
  def get_plan(sql, options = {})
    # Execute EXPLAIN for MySQL
    result = connection.query("EXPLAIN FORMAT=JSON #{sql}")
    JSON.parse(result.first.first)
  end

  def can_explain?(sql)
    # MySQL EXPLAIN restrictions
    normalized = sql.strip.upcase
    !normalized.start_with?("DROP", "ALTER", "CREATE")
  end

  def engine_name
    :mysql
  end
end

# Register:
mysql_adapter = MySQLAdapter.new(connection)
enricher = QueryGuard::Explain::ExplainEnricher.new(mysql_adapter)
QueryGuard.config.explain_enricher = enricher
```

## Production Considerations

### Performance Impact

| Analysis Type | Time | Safe for Prod? | Notes |
|---|---|---|---|
| Heuristic only | <1ms | Yes | Pattern matching |
| EXPLAIN (no ANALYZE) | 5-20ms | Yes | Plan estimation |
| EXPLAIN (with ANALYZE) | 50-500ms | No | Runs actual queries |

### Safe Configuration for Production

```ruby
QueryGuard.configure do |config|
  config.analyze_query_risks = true
  config.use_explain_plans = false  # Don't use EXPLAIN in prod
end

# OR: Selective EXPLAIN for slow queries only
QueryGuard.config.setup_postgresql_explain(
  connection,
  timeout: 2.0,        # Shorter timeout
  use_analyze: false   # Never run queries
)
```

### Sampling Strategy

In production, run EXPLAIN selectively:

```ruby
class SelectiveExplainMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    # Only analyze 1% of requests
    if rand < 0.01 && defined?(QueryGuard)
      QueryGuard.config.use_explain_plans = true
    else
      QueryGuard.config.use_explain_plans = false
    end

    @app.call(env)
  ensure
    QueryGuard.config.use_explain_plans = false  # Reset
  end
end
```

## Advanced: Index Creation Tips

When EXPLAIN detects missing indexes:

```ruby
# EXPLAIN shows: Sequential scan on users WHERE email = 'test@example.com'

# 1. Analyze the filter condition
sql = "SELECT COUNT(*) FROM users WHERE email = 'test@example.com'"
adapter.get_plan(sql)

# 2. Check cardinality
connection.execute("SELECT DISTINCT COUNT(email) FROM users")

# 3. Create index
connection.execute("CREATE INDEX CONCURRENTLY idx_users_email ON users(email)")

# 4. Gather new statistics
connection.execute("ANALYZE users")

# 5. Re-run EXPLAIN
adapter.get_plan("SELECT * FROM users WHERE email = 'test@example.com'")
# Should now show: Index Scan using idx_users_email
```

## Maintenance

### Update Statistics Regularly

PostgreSQL's query planner uses statistics to make decisions. Keep them fresh:

```ruby
# In a scheduled job:
connection.execute("ANALYZE")  # All tables
# OR
connection.execute("ANALYZE users")  # Specific table
```

### Monitor EXPLAIN Accuracy

```ruby
# Track how often estimates are wildly inaccurate:
Rails.logger.info("[QueryGuard] Plan estimate off by 15x - run ANALYZE")

# When this happens frequently, set up automated ANALYZE:
# config/schedule.yml (whenever gem)
every 1.hour do
  rake "db:analyze"
end
```

## Troubleshooting

### EXPLAIN returns "Cannot Execute This Query Type"

Some queries can't be EXPLAINED:
- `CREATE TABLE` (use `CREATE TABLE AS`)
- `INSERT` with non-SELECT source
- `DROP` operations
- `TRUNCATE`

### "EXPLAIN took too long, timing out"

Increase timeout or reduce query complexity:

```ruby
QueryGuard.config.setup_postgresql_explain(
  connection,
  timeout: 30.0  # Increase from default 5s
)

# OR disable EXPLAIN for development:
QueryGuard.config.use_explain_plans = false
```

### "Estimate accuracy ratio very high (100x)"

Your table statistics are stale:

```ruby
# Run ANALYZE:
connection.execute("ANALYZE")

# Check last analyze time:
connection.execute("""
  SELECT schemaname, tablename, last_analyze, last_autoanalyze
  FROM pg_stat_user_tables
  WHERE tablename = 'users'
""")
```

## Design Principles

1. **Safety First**: Only EXPLAIN, don't ANALYZE by default
2. **Extensible**: Adapter pattern supports future databases
3. **Non-Breaking**: EXPLAIN is optional; graceful degradation
4. **Observable**: All errors logged, never crashes analyzer
5. **Test-Friendly**: Mock EXPLAIN payloads, no DB deps in tests

## Testing

### Without Real Database

The test suite uses mocked EXPLAIN payloads:

```ruby
# spec/explain/explain_enricher_spec.rb

def default_sequential_scan_plan
  {
    "Plan" => {
      "Node Type" => "Seq Scan",
      "Relation Name" => "users",
      "Estimated Rows" => 1000,
      "Total Cost" => 35.50
    },
    "Planning Time" => 0.234,
    "Execution Time" => 2.543
  }
end

# Use in tests:
mock_adapter.set_plan_result(default_sequential_scan_plan)
```

Run tests:
```bash
bundle exec rspec spec/explain/
```

### Sample EXPLAIN Outputs

See `spec/explain/plan_signals_spec.rb` for real PostgreSQL examples:
- Sequential scans
- Index scans
- Nested joins
- High-cost queries
- ANALYZE accuracy data

## Future Enhancements

- **MySQL EXPLAIN support**
- **SQLite EXPLAIN QUERY PLAN**
- **Persistent plan history** (track optimization effectiveness)
- **Automated index suggestions** with confidence scoring
- **Query rewrite suggestions** based on plan analysis
- **Cost-based shaping** (identify most expensive queries)

## See Also

- [RISK_ANALYSIS.md](RISK_ANALYSIS.md) - Heuristic detection guide
- [PHASE_4_SUMMARY.md](PHASE_4_SUMMARY.md) - Phase 4 architecture
- [PostgreSQL EXPLAIN Docs](https://www.postgresql.org/docs/current/sql-explain.html)

## Examples

### Example 1: Detect Unindexed Search

```
QueryGuard Config:
  use_explain_plans = true

Your Code:
  User.where(email: 'user@example.com')

QueryGuard Detection:
  1. Heuristic (Phase 4): No pattern detected - looks fine
  2. EXPLAIN (Phase 5): Sequential scan on users table detected!
  
Finding:
  Title: Sequential Table Scan Detected
  SQL: SELECT * FROM users WHERE email = $1
  Severity: ERROR
  Recommendation: Add index on email column
```

### Example 2: Identify N+1 with Plan Data

```
Actual Request:
  1 initial query: SELECT * FROM users (1ms)
  5 N+1 queries: SELECT * FROM orders WHERE user_id = ? (5x 2ms each)
  Total: 11ms

EXPLAIN Analysis:
  - Initial query: Full seq scan expected (no index)
  - N+1 queries: Could use index on user_id
  
Recommendation:
  - Add index on orders(user_id)
  - Or: Eager load with includes(:orders)
```

### Example 3: Estimate Accuracy Alert

```
Query: SELECT * FROM users WHERE created_at > '2025-01-01'

EXPLAIN Output:
  Estimated Rows: 1000
  Actual Rows: 50000 (50x off!)

Finding:
  Title: Query Plan Estimate Inaccuracy
  Ratio: 50.0
  Severity: WARN
  Recommendation: Run ANALYZE to update statistics

System Response:
  connection.execute("ANALYZE users")
  # Re-run query - now estimate is accurate
```

## Performance Benchmarks

```
Test Environment: PostgreSQL 14, 1M row table

Operation          Time    Notes
─────────────────────────────────────────
Seq Scan (no EXPLAIN)     ~2ms
EXPLAIN Seq Scan          ~8ms    (+6ms)
EXPLAIN + ANALYZE         ~150ms  (+150ms, runs actual query)

With 50 queries/request:
  Heuristic only:    <50ms
  + EXPLAIN:         ~300-400ms (6-8ms per query)
  + EXPLAIN+ANALYZE: ~5000-7000ms (too slow!)
```

Always use `use_analyze: false` in production.
