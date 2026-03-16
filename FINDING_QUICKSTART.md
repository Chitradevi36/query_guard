# QueryGuard Finding Model: Quick Start

**For gem developers building custom analyzers and reporters.**

---

## TL;DR: Create a Finding in 3 Ways

### Option 1: Using a Factory Builder (Recommended)

```ruby
query = QueryGuard::Core::Query.new(sql: "SELECT...", duration_ms: 250)

# Slow Query
finding = QueryGuard::Core::FindingBuilders.slow_query(
  query,
  duration_ms: 250,
  threshold_ms: 100
)

# Too Many Queries
finding = QueryGuard::Core::FindingBuilders.too_many_queries(
  count: 150,
  limit: 100,
  total_duration_ms: 5000
)

# SELECT *
finding = QueryGuard::Core::FindingBuilders.select_star(query)

# Custom
finding = QueryGuard::Core::FindingBuilders.build(
  analyzer_name: :my_analyzer,
  rule_name: :my_rule,
  message: "My issue"
)
```

### Option 2: Direct Constructor (Full Control)

```ruby
finding = QueryGuard::Core::Finding.new(
  analyzer_name: :my_analyzer,
  rule_name: :my_rule,
  severity: :error,
  title: "Issue Title",
  description: "Detailed description",
  message: "Short message",
  file_path: "app.rb",
  line_number: 42,
  sql: "SELECT 1",
  metadata: { key: "value" },
  recommendations: ["Fix A", "Fix B"],
  query: query
)
```

### Option 3: Minimal Constructor (All Defaults)

```ruby
finding = QueryGuard::Core::Finding.new(
  analyzer_name: :my_rule,
  rule_name: :detected,
  message: "Found an issue"
)
# severity defaults to :warn
# recommendations defaults to []
# All location fields default to nil
```

---

## Finding Fields Reference

### Identification
```ruby
finding.analyzer_name  # Symbol - identifies which analyzer found it
finding.rule_name      # Symbol - specific rule within analyzer
finding.id             # String - deterministic ID (SHA256 hash, first 16 chars)
```

### Severity & Status
```ruby
finding.severity       # Symbol - :info, :warn, or :error
finding.created_at     # Time - when finding was created
```

### User-Facing Text
```ruby
finding.title          # String - short title
finding.description    # String - detailed explanation
finding.message        # String - primary message
finding.recommendations # Array<String> - suggested fixes
```

### Location & Context
```ruby
finding.file_path      # String - where issue occurred (e.g., "app/models/user.rb")
finding.line_number    # Integer - line number
finding.sql            # String - SQL statement
finding.query          # Query object - full query metadata
```

### Additional Data
```ruby
finding.metadata       # Hash - analyzer-specific context
finding.has_location?  # Boolean - true if file_path is set
```

---

## Serialization

### For Logging
```ruby
puts finding.to_s
# => "[ERROR] slow_query:duration_exceeded - Query exceeded 100ms"

puts finding.to_log_s
# => "[ERROR] slow_query:duration_exceeded - Query exceeded 100ms | File: app/models/user.rb:42 | SQL: SELECT..."
```

### For JSON/API
```ruby
json = finding.to_json_h
# Excludes query object, truncates SQL to 500 chars
# Safe for transmission over HTTP
```

### For Internal Use
```ruby
hash = finding.to_h
# Complete representation including query object
# Use for non-JSON serialization
```

---

## Using Findings in Analyzers

```ruby
class MyAnalyzer < QueryGuard::Analyzers::Base
  def initialize
    super(:my_analyzer)
  end

  def analyze(context, config)
    findings = []

    context.queries.each do |query|
      if query.duration_ms > 1000
        findings << QueryGuard::Core::FindingBuilders.slow_query(
          query,
          duration_ms: query.duration_ms,
          threshold_ms: 1000,
          severity: :error
        )
      end
    end

    findings
  end
end
```

Register it:
```ruby
QueryGuard.configure do |c|
  c.register_analyzer(:my_analyzer, MyAnalyzer.new)
end
```

---

## Using Findings in Reporters

```ruby
context = Thread.current[:query_guard_context]

context.findings.each do |finding|
  if finding.severity == :error
    # Report to CI
    puts "::error file=#{finding.file_path},line=#{finding.line_number}::#{finding.message}"
  end
  
  # Or to Slack
  send_to_slack(finding.to_json_h)
  
  # Or to database
  ViolationLog.create(finding.to_h)
end
```

---

## Common Metadata Patterns

### Slow Query Analyzer
```ruby
metadata = {
  duration_ms: 250.5,
  threshold_ms: 100.0
}
```

### Query Count Analyzer
```ruby
metadata = {
  count: 150,
  limit: 100,
  total_duration_ms: 5000.0
}
```

### SELECT * Analyzer
```ruby
metadata = {
  sql: "SELECT * FROM users"
}
```

### Custom Analyzer
```ruby
metadata = {
  pattern: "potential_n_plus_one",
  query_count: 5,
  table: "users"
}
```

### Migration Analyzer (Phase 2)
```ruby
metadata = {
  migration_type: :column_drop,
  table: "users",
  column: "email",
  data_loss_risk: true
}
```

---

## Working with Finding Severity

```ruby
# Severity values
:info   # Informational, not a problem
:warn   # Warning, should be reviewed
:error  # Error, should be fixed

# Set custom severity
QueryGuard.configure do |c|
  c.slow_query_severity = :error    # All slow queries are errors
  c.query_count_severity = :warn    # Too many queries are warnings
  c.select_star_severity = :info    # SELECT * is just info
end

# Or per-finding
finding = QueryGuard::Core::FindingBuilders.slow_query(
  query,
  duration_ms: 100,
  threshold_ms: 50,
  severity: :error  # Override default
)
```

---

## Deduplicating Findings

Findings are hashable and can be used in Sets:

```ruby
findings_list = [
  finding1,  # slow_query on SELECT * FROM users
  finding2,  # slow_query on SELECT * FROM users (same SQL, location)
  finding3   # different query
]

unique_findings = Set.new(findings_list)
unique_findings.size  # => 2 (duplicates removed by ID)

# ID is deterministic based on content
finding1.id == finding2.id  # => true
finding1.id == finding3.id  # => false
```

---

## Testing Findings

```ruby
describe "MyAnalyzer" do
  it "creates findings" do
    query = QueryGuard::Core::Query.new(sql: "SELECT 1", duration_ms: 100)
    analyzer = MyAnalyzer.new
    config = QueryGuard::Config.new
    context = QueryGuard::Core::Context.new
    context.add_query(sql: "SELECT 1", duration_ms: 100)

    findings = analyzer.analyze(context, config)

    expect(findings).not_to be_empty
    expect(findings[0]).to be_a(QueryGuard::Core::Finding)
    expect(findings[0].severity).to eq(:warn)
    expect(findings[0].recommendations).not_to be_empty
    expect(findings[0].to_h).to have_key(:id)
  end
end
```

---

## Finding Lifecycle

```
1. Create Query
   query = QueryGuard::Core::Query.new(...)

2. Analyzer produces Finding
   finding = FindingBuilders.slow_query(query, ...)
   
3. Finding stored in Context
   context.add_finding(finding)
   
4. Middleware processes Findings
   findings = analyzer_registry.analyze(context, config)
   
5. Reporter formats Findings
   json = finding.to_json_h
   log_s = finding.to_log_s
   
6. Action taken (log, raise, report)
   logger.warn(finding.to_log_s)
   # or
   send_to_ci(finding)
   # or
   send_to_saas_api(finding.to_json_h)
```

---

## Immutability

All strings and arrays are frozen:

```ruby
finding.title << " extra"        # FrozenError
finding.recommendations << "new" # FrozenError
finding.metadata["key"] = "val"  # FrozenError (hash frozen)

# This is intentional: Findings are immutable facts
```

---

## Backward Compatibility

✅ Fully backward compatible with v0.4.2

Old code still works:
```ruby
# v0.4.2 way
violation = { type: :slow_query, duration_ms: 250 }

# v0.5.0 way
finding = QueryGuard::Core::FindingBuilders.slow_query(
  query,
  duration_ms: 250,
  threshold_ms: 100
)

# Both coexist during transition
```

---

## Next Steps

- Read [FINDING_MODEL.md](FINDING_MODEL.md) for detailed reference
- Check [spec/core/finding_builders_spec.rb](spec/core/finding_builders_spec.rb) for examples
- See [DESIGN.md](DESIGN.md) for architecture overview

---

## Common Tasks

### Create a slow query finding
```ruby
QueryGuard::Core::FindingBuilders.slow_query(
  query,
  duration_ms: 250.5,
  threshold_ms: 100.0
)
```

### Log a finding
```ruby
logger.warn(finding.to_log_s)
```

### Send to CI
```ruby
puts "::error file=#{finding.file_path},line=#{finding.line_number}::#{finding.message}" if finding.file_path
```

### Serialize for API
```ruby
json = JSON.generate(finding.to_json_h)
```

### Check if it's an error
```ruby
if finding.severity == :error
  raise QueryGuard::Error, finding.message
end
```

### Get actionable suggestions
```ruby
finding.recommendations.each { |rec| puts "💡 #{rec}" }
```
