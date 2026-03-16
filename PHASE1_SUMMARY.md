# Phase 1: Refactored Folder Structure & Quick Reference

## New Folder Structure

```
lib/query_guard/
├── query_guard.rb                [Updated: require core modules + analyzers]
├── version.rb                    [Updated to 0.5.0]
├── config.rb                     [Refactored: analyzer registry + severities]
├── middleware.rb                 [Refactored: delegates to analyzer registry]
├── subscriber.rb                 [Enhanced: populates Context + legacy path]
├── client.rb                     [Unchanged for now]
│
├── core/                         [NEW: Core data models]
│   ├── query.rb                  [Immutable SQL event model]
│   ├── finding.rb                [Immutable violation result]
│   └── context.rb                [Request state + queries + findings]
│
└── analyzers/                    [NEW: Rule-based analyzer system]
    ├── base.rb                   [Abstract analyzer interface]
    ├── registry.rb               [Manages analyzer lifecycle]
    ├── slow_query_analyzer.rb    [Duration threshold check]
    ├── query_count_analyzer.rb   [Query count threshold check]
    └── select_star_analyzer.rb   [SELECT * pattern detection]

spec/
├── spec_helper.rb               [Existing]
├── query_guard_spec.rb          [Existing: placeholder test]
├── config_spec.rb               [NEW: Config with analyzers]
├── core/                        [NEW: Core model tests]
│   ├── query_spec.rb
│   ├── finding_spec.rb
│   └── context_spec.rb
├── analyzers/                   [NEW: Analyzer tests]
│   ├── base_spec.rb
│   └── analyzers_spec.rb        [SlowQuery, QueryCount, SelectStar]
└── integration/                 [NEW: Full flow tests]
    └── full_flow_spec.rb
```

## Public API Changes

### Config: New Methods

```ruby
config.disable_analyzer(name)      # Disable :slow_query, :query_count, :select_star
config.enable_analyzer(name)       # Re-enable
config.register_analyzer(name, analyzer)  # Custom analyzer
config.analyzer_registry           # Access registry for introspection
```

### Config: New Attributes

```ruby
config.slow_query_severity         # :info, :warn, :error (default :warn)
config.query_count_severity        # :info, :warn, :error (default :warn)
config.select_star_severity        # :info, :warn, :error (default :warn)
config.disabled_analyzers          # Array of disabled analyzer names
```

### Backward Compat: Existing Still Works

```ruby
config.max_queries_per_request     # ✓ Still configures QueryCountAnalyzer
config.max_duration_ms_per_query   # ✓ Still configures SlowQueryAnalyzer
config.block_select_star           # ✓ Still enables SelectStarAnalyzer
config.ignored_sql                 # ✓ Still used by all analyzers
config.raise_on_violation          # ✓ Still raises on any findings
```

## Class Hierarchy

```
QueryGuard
├── Core
│   ├── Query          (Immutable SQL event)
│   ├── Finding        (Immutable violation result)
│   └── Context        (Request state container)
│
├── Analyzers
│   ├── Base           (Abstract interface)
│   ├── Registry       (Analyzer manager)
│   ├── SlowQueryAnalyzer
│   ├── QueryCountAnalyzer
│   └── SelectStarAnalyzer
│
├── Config             (Configuration + registry)
├── Middleware        (Request middleware)
├── Subscriber        (SQL event listener)
└── Client            (HTTP client, unchanged)
```

## Migration Checklist for Users

- [ ] Upgrade gem to v0.5.0
- [ ] No code changes needed for existing projects
- [ ] Optionally: Set per-analyzer severities
- [ ] Optionally: Disable unwanted analyzers
- [ ] Optionally: Register custom analyzers

## Example: Full Configuration

```ruby
QueryGuard.configure do |c|
  # Existing config (unchanged)
  c.enabled_environments = %i[development test]
  c.max_queries_per_request = 100
  c.max_duration_ms_per_query = 100.0
  c.block_select_star = false
  c.raise_on_violation = false
  c.ignored_sql = [/^PRAGMA /i, /^BEGIN/i]
  
  # New: Severities per analyzer
  c.slow_query_severity = :error      # Raise on slow queries
  c.query_count_severity = :warn      # Warn on too many queries
  c.select_star_severity = :info      # Info on SELECT *
  
  # New: Disable specific analyzers
  c.disable_analyzer(:select_star)    # Don't check for SELECT *
  
  # New: Register custom analyzer
  c.register_analyzer(:my_rule, MyCustomAnalyzer.new)
end
```

## Example: Custom Analyzer

```ruby
class MyCustomAnalyzer < QueryGuard::Analyzers::Base
  def initialize
    super(:my_rule)
  end

  def analyze(context, config)
    findings = []
    context.queries.each do |query|
      if query.sql =~ /\bDROP\b/i
        findings << QueryGuard::Core::Finding.new(
          analyzer_name: name,
          rule_name: :drop_detected,
          severity: :error,
          message: "DROP statement detected in query",
          metadata: { sql: query.sql },
          query: query
        )
      end
    end
    findings
  end
end

# Register in config
QueryGuard.configure do |c|
  c.register_analyzer(:drop_detector, MyCustomAnalyzer.new)
end
```

## Data Structures

### Query
```ruby
query = QueryGuard::Core::Query.new(
  sql: "SELECT * FROM users",
  duration_ms: 125.45,
  name: "User Load",
  started_at: Time.now,
  finished_at: Time.now + 0.125
)
# Methods: to_h, inspect, ==(other)
```

### Finding
```ruby
finding = QueryGuard::Core::Finding.new(
  analyzer_name: :slow_query,        # Symbol
  rule_name: :duration_exceeded,     # Symbol
  severity: :warn,                   # :info, :warn, :error
  message: "Query exceeded threshold", # String
  metadata: { duration_ms: 250 },    # Hash
  query: query                        # Optional Query object
)
# Methods: to_h, to_s, ==(other)
# Validations: severity must be one of SEVERITIES
```

### Context
```ruby
context = QueryGuard::Core::Context.new
context.add_query(sql: "SELECT 1", duration_ms: 10, ...)
context.create_finding(analyzer_name: :x, rule_name: :y, ...)
# Accessors: queries, findings
# Methods: query_count, total_duration_ms, finding_count, findings_by_severity, clear, to_h
```

## Logging Format (Unchanged)

```
[QueryGuard] [WARN] slow_query:duration_exceeded - Query exceeded slow threshold: 250.25ms > 100.0ms
[QueryGuard] [ERROR] query_count:count_exceeded - Too many queries: 150 > 100
[QueryGuard] [WARN] select_star:select_star_detected - SELECT * detected in query
```

## Backwards Compatibility

| Feature | v0.4.2 | v0.5.0 | Notes |
|---------|--------|--------|-------|
| Rails middleware integration | ✓ | ✓ | Auto-installed via Railtie |
| Config thresholds | ✓ | ✓ | Still configure behavior |
| Exception raising | ✓ | ✓ | `raise_on_violation` works |
| Logging format | ✓ | ✓ | Same message structure |
| Analyzer disabling | ✗ | ✓ | New feature |
| Custom severities | ✗ | ✓ | New feature |
| Custom analyzers | ✗ | ✓ | New feature |
| Thread.current access | ✓ | ✓ | Legacy path maintained |
| Context object | ✗ | ✓ | New, internal API |

## Testing Primitives Added

### Spec Helpers (use in integration tests)

```ruby
def mock_sql_event(name, sql, duration_seconds)
  started = Time.now
  finished = started + duration_seconds
  
  ActiveSupport::Notifications.publish(
    "sql.active_record",
    started,
    finished,
    SecureRandom.uuid,
    name: name,
    sql: sql
  )
end
```

### Test Fixtures (spec/fixtures/)

Available for use:
- Safe queries (fast, specific columns, no patterns)
- Slow queries (>100ms)
- Too many queries (>100 per request)
- SELECT * queries
- Ignored SQL patterns
