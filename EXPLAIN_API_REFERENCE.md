# PostgreSQL EXPLAIN API Reference

## Module Structure

```
QueryGuard::Explain
  ├── AdapterInterface (base class)
  ├── PostgreSQLAdapter (PostgreSQL implementation)
  ├── PlanSignals
  │   ├── PlanNode
  │   ├── QueryPlan
  │   └── PlanSignals
  └── ExplainEnricher
```

## AdapterInterface

Base class for database-specific adapters.

### Methods

#### `initialize(connection)`
Initialize adapter with database connection.

**Parameters**:
- `connection` - Database-specific connection object

#### `get_plan(sql, options = {})`
Execute EXPLAIN and return parsed JSON plan.

**Parameters**:
- `sql` (String) - SQL query to analyze
- `options` (Hash) - Adapter-specific options
  - `:use_analyze` (Boolean) - Override default ANALYZE flag

**Returns**: (Hash) Parsed EXPLAIN JSON
```ruby
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
```

**Raises**:
- `UnsupportedQueryError` - Query type not safe to explain
- `ConnectionError` - Database connection failed
- `TimeoutError` - EXPLAIN query timed out
- `PlanParseError` - Invalid JSON in response

#### `can_explain?(sql)`
Check if query can be safely explained.

**Parameters**:
- `sql` (String) - SQL query

**Returns**: Boolean

#### `engine_name`
Get database engine identifier.

**Returns**: Symbol (`:postgresql`, `:mysql`, etc.)

### Error Classes

#### `AdapterError`
Base error for EXPLAIN failures.

**Attributes**:
- `message` - Error description
- `query` - SQL query (if available)
- `original_error` - Underlying exception

#### `UnsupportedQueryError < AdapterError`
Query type cannot be explained (DDL, transactions, etc.)

#### `ConnectionError < AdapterError`
Database connection unavailable or invalid.

#### `TimeoutError < AdapterError`
EXPLAIN query exceeded timeout.

#### `PlanParseError < AdapterError`
Failed to parse EXPLAIN JSON output.

## PostgreSQLAdapter

PostgreSQL-specific implementation.

### Initialization

```ruby
adapter = PostgreSQLAdapter.new(
  connection,
  timeout: 5.0,              # Seconds (default: 5.0)
  use_analyze: false,        # Default false for safety
  logger: Rails.logger,      # Optional
  validate_connection: true  # Check connection on init
)
```

**Query Validation**:
- ✅ Allows: SELECT, WITH (CTEs), UPDATE, DELETE
- ❌ Rejects: CREATE, DROP, ALTER, TRUNCATE, PRAGMA, transactions

### Methods

#### `get_plan(sql, options = {})`
See AdapterInterface

#### `can_explain?(sql)`
See AdapterInterface

#### `engine_name`
Returns `:postgresql`

#### `server_version`
Get PostgreSQL server version.

**Returns**: String (e.g., "PostgreSQL 13.0")
**Raises**: ConnectionError if unavailable

## PlanSignals Classes

### PlanNode

Represents single node in query plan tree.

**Attributes** (read-only):
- `node_type` (String) - Node type (Seq Scan, Index Scan, etc.)
- `relation_name` (String) - Table name
- `index_name` (String) - Index name (if applicable)
- `depth` (Integer) - Nesting level in tree
- `estimated_rows` (Integer) - Planner estimate
- `estimated_cost` (Float) - Total cost estimate
- `actual_rows` (Integer) - Actual rows (ANALYZE only)
- `actual_duration_ms` (Float) - Actual time (ANALYZE only)
- `filter` (String) - WHERE condition
- `sort_key` (String) - ORDER BY clause
- `children` (Array<PlanNode>) - Child nodes

**Methods**:

#### `sequential_scan?`
Returns true if node is a sequential scan.

#### `index_scan?`
Returns true if node uses an index.

#### `sequential_scans`
Returns array of all sequential scans in subtree.

#### `nodes_of_type(type)`
Find all nodes of given type in subtree.
```ruby
node.nodes_of_type("Nested Loop")  # => [PlanNode, ...]
```

#### `estimate_accuracy_ratio`
Calculate actual vs estimated row ratio.
```ruby
node.estimate_accuracy_ratio  # => 1.5 (50% more rows)
# Returns nil if no actual data
```

#### `estimate_inaccurate?(threshold = 10)`
Check if estimate is significantly off.
```ruby
node.estimate_inaccurate?      # => true if > 10x off
node.estimate_inaccurate?(5)   # => true if > 5x off
```

#### `to_h`
Convert to hash for serialization.

### QueryPlan

Wrapper for complete EXPLAIN output.

**Attributes** (read-only):
- `root_node` (PlanNode) - Top-level plan node
- `planning_time_ms` (Float) - Planning duration
- `execution_time_ms` (Float) - Execution duration
- `triggers` (Array) - Trigger details

**Methods**:

#### `sequential_scans`
Find all sequential scans in entire plan.

#### `scans_for_table(table_name)`
Find scans for specific table.
```ruby
plan.scans_for_table("users")  # => [PlanNode, ...]
```

#### `uses_indexes?`
Check if plan uses any indexes.

#### `total_estimated_cost`
Get root node total cost.

#### `to_h`
Convert to hash for serialization.

### PlanSignals

Extract actionable signals from query plan.

**Attributes** (read-only):
- `plan` (QueryPlan) - Source plan
- `signals` (Array<Hash>) - Extracted signals
- `extracted_at` (Time) - Extraction timestamp

**Signal Hash Structure**:
```ruby
{
  type: :sequential_scan,           # Signal type
  severity: :high,                  # :high, :medium, :low
  message: "Sequential scan on...",
  recommendation: "Consider adding...",
  # Type-specific fields (table, filter, cost, ratio, etc.)
}
```

**Signal Types**:
1. `:sequential_scan` - Row-by-row scan
2. `:likely_missing_index` - Sequential scan with filter
3. `:high_estimated_cost` - Cost > 10,000
4. `:nested_loop_join` - Inner loop join detected
5. `:estimate_inaccuracy` - Planner estimate > 10x off
6. `:expensive_sort` - Sort on large result set
7. `:high_planning_time` - Planning time > 100ms
8. `:bitmap_scan` - Bitmap index scan

**Methods**:

#### `to_a`
Returns all signals as array.

#### `signals_of_type(type)`
Filter signals by type.
```ruby
plan_signals.signals_of_type(:sequential_scan)  # => [signal1, ...]
```

#### `critical_signals(severity)`
Filter by severity (`:high`, `:medium`, `:low`).
```ruby
plan_signals.critical_signals(:high)
```

#### `to_h`
Convert to hash (includes plan and signals).

## ExplainEnricher

Convert EXPLAIN signals to Finding objects.

### Initialization

```ruby
enricher = ExplainEnricher.new(
  adapter,
  logger: Rails.logger,  # Optional
  custom_option: value   # Additional config
)
```

### Methods

#### `enrich(findings, query, context = nil)`
Enrich findings with EXPLAIN analysis.

**Parameters**:
- `findings` (Array<Core::Finding>) - Existing findings
- `query` (Core::Query) - Query to analyze
- `context` (Core::Context) - Optional request context

**Returns**: Array<Core::Finding> - Original + new findings

**Behavior**:
- Returns original findings if nil
- Returns original findings if EXPLAIN fails (graceful degradation)
- Appends new findings from EXPLAIN analysis

#### `can_enrich?(query)`
Check if query can be analyzed.

**Returns**: Boolean

**Condition**:
- Query not nil
- Query.sql not nil
- Adapter can explain query

### Converted Findings

Each signal type produces a Finding:

#### Sequential Scan Finding
```ruby
{
  analyzer_name: :query_risk,
  rule_name: :sequential_scan_via_explain,
  severity: :error,
  title: "Sequential Table Scan Detected",
  description: "Query uses sequential scan; table is scanned row-by-row",
  metadata: {
    table: "users",
    estimated_rows: 1000,
    source: "PostgreSQL EXPLAIN"
  }
}
```

#### Missing Index Finding
```ruby
{
  analyzer_name: :query_risk,
  rule_name: :missing_index_via_explain,
  severity: :error,
  title: "Missing Index Detected",
  metadata: {
    table: "users",
    filter: "(status = 'active')",
    source: "PostgreSQL EXPLAIN"
  }
}
```

#### Nested Loop Join Finding
```ruby
{
  analyzer_name: :query_risk,
  rule_name: :nested_loop_join,
  severity: :warn,
  title: "Nested Loop Join Detected",
  metadata: {
    inner_table: "orders",
    source: "PostgreSQL EXPLAIN"
  }
}
```

#### High Planning Time Finding
```ruby
{
  analyzer_name: :query_risk,
  rule_name: :high_planning_time,
  severity: :info,
  title: "High Query Planning Time",
  metadata: {
    planning_time_ms: 150.5,
    source: "PostgreSQL EXPLAIN"
  }
}
```

#### Expensive Sort Finding
```ruby
{
  analyzer_name: :query_risk,
  rule_name: :expensive_sort,
  severity: :warn,
  title: "Expensive Sort Operation",
  metadata: {
    estimated_rows: 5000,
    source: "PostgreSQL EXPLAIN"
  }
}
```

#### Estimate Inaccuracy Finding
```ruby
{
  analyzer_name: :query_risk,
  rule_name: :estimate_inaccuracy,
  severity: :warn,
  title: "Query Plan Estimate Inaccuracy",
  metadata: {
    node: "Seq Scan on users",
    accuracy_ratio: 15.5,
    source: "PostgreSQL EXPLAIN ANALYZE"
  }
}
```

#### High Query Cost Finding
```ruby
{
  analyzer_name: :query_risk,
  rule_name: :high_query_cost,
  severity: :warn,
  title: "High Query Cost Estimated",
  metadata: {
    estimated_cost: 12500.0,
    source: "PostgreSQL EXPLAIN"
  }
}
```

#### Bitmap Scan Finding
```ruby
{
  analyzer_name: :query_risk,
  rule_name: :bitmap_scan,
  severity: :info,
  title: "Bitmap Index Scan",
  metadata: {
    table: "products",
    source: "PostgreSQL EXPLAIN"
  }
}
```

## QueryGuard::Config

Configuration methods for EXPLAIN support.

### Methods

#### `setup_postgresql_explain(connection, options = {})`
Configure PostgreSQL EXPLAIN adapter and enricher.

**Parameters**:
- `connection` - ActiveRecord or pg connection
- `options` (Hash):
  - `:timeout` - Query timeout (default: 5.0)
  - `:use_analyze` - Enable ANALYZE (default: false)
  - `:logger` - Logger instance
  - `:validate_connection` - Check connection (default: true)

**Returns**: Boolean (success)

**Side Effects**:
- Sets `@explain_adapter`
- Sets `@explain_enricher`

**Example**:
```ruby
config.setup_postgresql_explain(
  ActiveRecord::Base.connection,
  timeout: 10,
  use_analyze: false,
  logger: Rails.logger
)
```

## Usage Examples

### Direct Adapter Usage
```ruby
adapter = QueryGuard::Explain::PostgreSQLAdapter.new(conn)
plan = adapter.get_plan("SELECT * FROM users WHERE id = 1")
puts plan["Planning Time"]  # => 0.234
```

### Plan Analysis
```ruby
plan = QueryGuard::Explain::PlanSignals::QueryPlan.new(plan_json)
puts plan.sequential_scans.count    # => 0 (good!)
puts plan.uses_indexes?             # => true
puts plan.total_estimated_cost      # => 0.42
```

### Signal Extraction
```ruby
signals = QueryGuard::Explain::PlanSignals::PlanSignals.new(plan)
signals.to_a.each do |signal|
  puts "#{signal[:type]}: #{signal[:message]}"
end
```

### Full Pipeline
```ruby
adapter = PostgreSQLAdapter.new(connection)
enricher = ExplainEnricher.new(adapter)
query = QueryGuard::Core::Query.new(sql: "SELECT...", duration_ms: 10)

findings = enricher.enrich([], query)
findings.each { |f| puts f.title }
```

## Extending for New Databases

Create new adapter:
```ruby
class MySQLAdapter < QueryGuard::Explain::AdapterInterface
  def initialize(connection, options = {})
    super(connection)
    @timeout = options[:timeout] || 5.0
  end

  def get_plan(sql, options = {})
    # 1. Validate query
    raise UnsupportedQueryError unless can_explain?(sql)
    
    # 2. Build and execute EXPLAIN
    explain_sql = "EXPLAIN FORMAT=JSON #{sql}"
    result = execute_query(explain_sql)
    
    # 3. Parse result
    JSON.parse(result)
  end

  def can_explain?(sql)
    normalized = sql.strip.upcase
    # MySQL-specific restrictions
    !normalized.start_with?("DROP", "ALTER", "CREATE")
  end

  def engine_name
    :mysql
  end

  private

  def execute_query(sql)
    @connection.query(sql).first.first
  end
end
```

## Testing

All components have mocked tests:

```ruby
# Mock adapter for testing
class MockAdapter
  def can_explain?(sql) = true
  def get_plan(sql) = { "Plan" => {...} }
end

# Use in tests
enricher = ExplainEnricher.new(MockAdapter.new)
findings = enricher.enrich([], query)
expect(findings).to have_length(1)
```

See `spec/explain/` for 165+ test examples.
