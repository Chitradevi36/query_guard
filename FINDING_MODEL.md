# QueryGuard Finding Model: Reference Guide

**Version:** 0.5.0  
**Last Updated:** March 2026

---

## Overview

The **Finding** model is the central data structure for reporting query issues and violations in QueryGuard. It's designed to be:

- **Rich:** Contains comprehensive information about detected issues
- **Immutable:** Frozen strings and hashes prevent accidental mutations
- **Serializable:** Can be converted to JSON for APIs, CI systems, and dashboards
- **Extensible:** New fields can be added without breaking existing code

---

## Finding Structure

### Core Fields

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `analyzer_name` | Symbol | ✓ | Name of the analyzer that found the issue (e.g., `:slow_query`) |
| `rule_name` | Symbol | ✓ | Specific rule within the analyzer (e.g., `:duration_exceeded`) |
| `severity` | Symbol | ✓ | Issue severity: `:info`, `:warn`, `:error` |
| `id` | String | ✓ (auto) | Deterministic ID for deduplication; first 16 chars of SHA256 hash |

### Message & Description

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `title` | String | ✗ | Short title (e.g., "Slow Query Detected") |
| `description` | String | ✗ | Detailed explanation (e.g., "Query execution time exceeded...") |
| `message` | String | ✓ | Primary message combining title/description and context |
| `recommendations` | Array<String> | ✓ (default: []) | Suggested fixes and improvements |

### Location Information

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `file_path` | String | ✗ | File where issue occurred (e.g., `app/models/user.rb`) |
| `line_number` | Integer | ✗ | Line number in file |

### Query Context

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `sql` | String | ✗ | SQL statement (limited to 500 chars in JSON) |
| `query` | Query | ✗ | Full Query object (excluded from JSON payloads) |
| `metadata` | Hash | ✓ (default: {}) | Additional context (analyzer-specific) |

### Timestamps

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `created_at` | Time | ✓ (auto) | When finding was created |

---

## Creating Findings

### Using Factory Builders (Recommended)

Factory builders provide well-structured findings with best practices baked in:

#### Slow Query Finding

```ruby
query = QueryGuard::Core::Query.new(
  sql: "SELECT * FROM users WHERE id = 1",
  duration_ms: 250.5
)

finding = QueryGuard::Core::FindingBuilders.slow_query(
  query,
  duration_ms: 250.5,
  threshold_ms: 100.0,
  severity: :error,  # Optional
  file_path: "app/models/user.rb",  # Optional
  line_number: 42  # Optional
)

# Result:
# finding.title = "Slow Query Detected"
# finding.description = "Query execution time exceeded..."
# finding.recommendations = ["Add indexes...", "Review and optimize...", ...]
```

#### Too Many Queries Finding

```ruby
finding = QueryGuard::Core::FindingBuilders.too_many_queries(
  count: 150,
  limit: 100,
  total_duration_ms: 5000.0,
  severity: :warn,  # Optional
  file_path: "app/controllers/users_controller.rb",  # Optional
  line_number: 25  # Optional
)

# Includes N+1 prevention recommendations
```

#### SELECT * Finding

```ruby
query = QueryGuard::Core::Query.new(sql: "SELECT * FROM posts", duration_ms: 50.0)

finding = QueryGuard::Core::FindingBuilders.select_star(
  query,
  severity: :info,  # Optional
  file_path: "db/seeds.rb",  # Optional
  line_number: 15  # Optional
)

# Includes column-specification best practice recommendations
```

#### Migration Risk Finding

```ruby
finding = QueryGuard::Core::FindingBuilders.migration_risk(
  migration_file: "db/migrate/001_create_users.rb",
  issue: "Removing NOT NULL constraint without safe guards",
  rule_name: :null_constraint_drop,  # Optional
  title: "Migration at Risk",  # Optional
  line_number: 10,  # Optional
  severity: :error  # Optional
)

# Includes migration-specific recommendations
```

#### Generic Builder

```ruby
finding = QueryGuard::Core::FindingBuilders.build(
  analyzer_name: :my_analyzer,
  rule_name: :my_rule,
  title: "My Issue",
  description: "Long description",
  message: "Short message",
  severity: :error,
  metadata: { custom: "data" },
  recommendations: ["Fix A", "Fix B"],
  query: query,  # Optional
  file_path: "app.rb",  # Optional
  line_number: 50  # Optional
)
```

### Manual Creation

For full control, you can create findings directly:

```ruby
finding = QueryGuard::Core::Finding.new(
  analyzer_name: :custom,
  rule_name: :custom_rule,
  title: "Custom Issue",
  description: "This is a custom issue",
  message: "Short form message",
  severity: :error,
  file_path: "app.rb",
  line_number: 42,
  sql: "SELECT 1",
  metadata: { key: "value" },
  recommendations: ["Do this", "Then that"],
  query: query  # Optional
)
```

---

## Finding Methods

### Querying Information

```ruby
# Check if finding has location info
finding.has_location?  # => true if file_path is set

# Access all fields
finding.analyzer_name    # => :slow_query
finding.rule_name        # => :duration_exceeded
finding.severity         # => :error
finding.title            # => "Slow Query Detected"
finding.message          # => "Query exceeded 100ms"
finding.file_path        # => "app/models/user.rb"
finding.line_number      # => 42
finding.sql              # => "SELECT * FROM users"
finding.metadata         # => { duration_ms: 250.5, ... }
finding.recommendations  # => ["Add index", ...]
finding.query            # => <Query object>
finding.created_at       # => 2026-03-15 12:00:00 UTC

# Identification
finding.id               # => "a1b2c3d4e5f6g7h8"
```

### Comparison & Equality

```ruby
finding1 = QueryGuard::Core::FindingBuilders.slow_query(query, duration_ms: 100, threshold_ms: 50)
finding2 = QueryGuard::Core::FindingBuilders.slow_query(query, duration_ms: 100, threshold_ms: 50)

finding1 == finding2  # => true (same analyzer, rule, severity, message)
finding1.hash == finding2.hash  # => true (based on ID)

# Useful for Set deduplication
findings_set = Set.new([finding1, finding2])
findings_set.size  # => 1 (deduplicated by ID)
```

### Serialization

```ruby
# Complete hash representation
hash = finding.to_h
# {
#   id: "...",
#   analyzer: :slow_query,
#   rule: :duration_exceeded,
#   severity: :error,
#   title: "Slow Query Detected",
#   description: "...",
#   message: "...",
#   file_path: "app.rb",
#   line_number: 42,
#   sql: "SELECT 1...",
#   metadata: { ... },
#   recommendations: [ ... ],
#   created_at: "2026-03-15T12:00:00Z",
#   query: { sql: "...", duration_ms: 100, ... }
# }

# JSON-safe hash (excludes query object, truncates SQL)
json_hash = finding.to_json_h
# {
#   id: "...",
#   analyzer: :slow_query,
#   ... (no query field)
# }

# Human-readable strings
finding.to_s       # => "[ERROR] slow_query:duration_exceeded - Query exceeded 100ms"
finding.to_log_s   # => "[ERROR] slow_query:duration_exceeded - ... | File: app.rb:42 | SQL: SELECT 1..."
finding.inspect    # => "#<Finding id=a1b2c3d4 slow_query:duration_exceeded severity=error>"
```

---

## Finding Example: Complete Workflow

```ruby
# 1. Create a Query
query = QueryGuard::Core::Query.new(
  sql: "SELECT * FROM users WHERE id = 1",
  duration_ms: 250.5,
  name: "User Load",
  started_at: Time.now - 0.250,
  finished_at: Time.now
)

# 2. Create a Finding using builder
finding = QueryGuard::Core::FindingBuilders.slow_query(
  query,
  duration_ms: 250.5,
  threshold_ms: 100.0,
  severity: :error,
  file_path: "app/models/user.rb",
  line_number: 42
)

# 3. Inspect the finding
puts finding.to_s
# => "[ERROR] slow_query:duration_exceeded - Query took 250.5ms (limit: 100.0ms)"

puts finding.to_log_s
# => "[ERROR] slow_query:duration_exceeded - Query took 250.5ms (limit: 100.0ms) | 
#      File: app/models/user.rb:42 | SQL: SELECT * FROM users WHERE id = 1"

# 4. Serialize for reporting
json_payload = finding.to_json_h
puts JSON.pretty_generate(json_payload)
# => {
#      "id": "a1b2c3d4e5f6g7h8",
#      "analyzer": "slow_query",
#      "rule": "duration_exceeded",
#      "severity": "error",
#      "title": "Slow Query Detected",
#      "description": "Query execution time exceeded...",
#      "message": "Query took 250.5ms (limit: 100.0ms)",
#      "file_path": "app/models/user.rb",
#      "line_number": 42,
#      "sql": "SELECT * FROM users WHERE id = 1",
#      "metadata": { "duration_ms": 250.5, "threshold_ms": 100.0 },
#      "recommendations": [ ... ],
#      "created_at": "2026-03-15T12:00:00Z"
#    }

# 5. Use for CI integration
if finding.severity == :error
  puts "::error file=#{finding.file_path},line=#{finding.line_number}::#{finding.message}"
end

# 6. Deduplicate in a set
findings_set = Set.new([finding, finding.dup])  # Same ID
findings_set.size  # => 1
```

---

## Field Reference by Use Case

### For Logging/Console Output
- `analyzer_name`, `rule_name`, `severity`, `message`
- `to_s` or `to_log_s`

### For CI Integration (GitHub, GitLab)
- `analyzer_name`, `rule_name`, `severity`
- `file_path`, `line_number`
- `message`, `title`

### For JSON/API Payloads
- `to_json_h` (recommended)
- All public fields serialized except `query` object

### For Error Deduplication
- `id` (deterministic, content-based)
- Use in Set for deduplication

### For Rich Reporting/Dashboards
- All fields (use `to_h`)
- `recommendations` for actionable suggestions
- `metadata` for analyzer-specific context

---

## Metadata Patterns by Analyzer

Different analyzers populate metadata with relevant context:

### slow_query Analyzer
```ruby
metadata = {
  duration_ms: 250.5,
  threshold_ms: 100.0
}
```

### query_count Analyzer
```ruby
metadata = {
  count: 150,
  limit: 100,
  total_duration_ms: 5000.0
}
```

### select_star Analyzer
```ruby
metadata = {
  sql: "SELECT * FROM users"
}
```

### Custom Analyzers
Add any relevant context:
```ruby
metadata = {
  pattern_type: "potential_n_plus_one",
  suspicious_queries: 5,
  estimated_fix_time: "10 minutes"
}
```

---

## Recommendations Best Practices

Recommendations should be:
- **Actionable:** Users can follow them
- **Specific:** Not "optimize query" but "add index on user_id"
- **Diverse:** Multiple approaches when possible
- **Ordered:** Most important first

Example:
```ruby
recommendations: [
  "Add index on foreign_key column (most common fix)",
  "Review query logic for unnecessary columns",
  "Consider using pagination for large result sets",
  "Check database statistics are up-to-date"
]
```

---

## Immutability & Thread Safety

All string and array fields are frozen to prevent accidental mutations:

```ruby
finding.message << " MODIFIED"  # => FrozenError: can't modify frozen String
finding.recommendations << "New"  # => FrozenError: can't modify frozen Array

# Safe because immutable
thread1 = Thread.new { finding.message }
thread2 = Thread.new { finding.message }
# No race conditions
```

---

## Backward Compatibility Notes

Finding model is **new in v0.5.0** but maintains compatibility with older code:

- Old `Thread.current[:query_guard_stats]` still works (legacy path in Middleware)
- New analyzers return Findings (structured)
- Middleware logs both old and new formats temporarily
- v0.6.0+ will phase out legacy path

---

## Migration from v0.4.2 to v0.5.0

No breaking changes if you're using QueryGuard as a gem:

```ruby
# This still works exactly the same
QueryGuard.configure do |c|
  c.max_queries_per_request = 100
  c.max_duration_ms_per_query = 100.0
end

# Optionally use new features:
# - Custom severities: c.slow_query_severity = :error
# - Disable analyzers: c.disable_analyzer(:select_star)
# - Custom analyzers: c.register_analyzer(:my_rule, MyAnalyzer.new)
```

If you're accessing findings (internal API):

```ruby
# v0.4.2
violations = stats[:violations]  # Array of hashes

# v0.5.0
findings = analyzer_registry.analyze(context, config)  # Array of Finding objects
finding.to_h  # Convert to hash if needed
```

---

## Future Directions (Phase 2+)

The Finding model is designed to support:

1. **Migration Analysis (Phase 2):** More fields for DDL/migration context
2. **JSON Reporting (Phase 5):** Built-in serialization (already present)
3. **SaaS Integration (Phase 6):** API payloads (to_json_h designed for this)
4. **Custom Fields:** Extensible metadata for user-defined analyzers
5. **Suggestions AI:** Future `suggestions` field (different from `recommendations`)

---

## Testing Findings

```ruby
# RSpec example
describe "my analyzer" do
  it "creates a finding" do
    query = QueryGuard::Core::Query.new(sql: "SELECT 1", duration_ms: 100)
    finding = QueryGuard::Core::FindingBuilders.slow_query(
      query,
      duration_ms: 100,
      threshold_ms: 50
    )

    expect(finding).to be_a(QueryGuard::Core::Finding)
    expect(finding.severity).to eq(:warn)
    expect(finding.recommendations).not_to be_empty
    expect(finding.to_h).to have_key(:id)
  end
end
```
