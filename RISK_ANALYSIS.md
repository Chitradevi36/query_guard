# Query Risk Analyzer Guide

## Overview

The Query Risk Analyzer is a powerful component of QueryGuard that evaluates SQL queries for performance and safety risks. It analyzes both individual queries and request-level patterns to identify potential optimization opportunities and architectural issues.

## Features

### Risk Categories

The analyzer detects and classifies multiple types of SQL anti-patterns:

#### Query-Level Risks

1. **SELECT * Usage** (Medium Risk)
   - Fetching all columns often retrieves unnecessary data
   - Recommendation: Specify only required columns explicitly
   - Impact: Unnecessary data transfer, slower queries
   - Severity: WARN

2. **LIKE Without Index** (High Risk)
   - Pattern matching without indexes typically requires full table scans
   - Applies to: `LIKE '%value%'`, `LIKE '%value'`
   - Recommendation: Use full-text search or indexed prefix matching
   - Impact: Sequential table scans, slow performance
   - Severity: ERROR

3. **Function in JOIN Condition** (High Risk)
   - Functions in JOIN conditions prevent index usage
   - Example: `JOIN users ON LOWER(order.email) = LOWER(user.email)`
   - Recommendation: Denormalize data or use indexed columns directly
   - Impact: Full index scans instead of seeks
   - Severity: ERROR

4. **Complex Multi-Table Join** (Medium Risk)
   - Queries joining 5+ tables are difficult to optimize
   - Recommendation: Break into smaller queries or use materialized views
   - Impact: Complex query plans, difficult to maintain
   - Severity: WARN

5. **Nested Subqueries** (Medium/High Risk)
   - Subqueries can cause multiple table scans
   - Severity increases with nesting depth (1 = medium, 3+ = high)
   - Recommendation: Use JOINs or CTEs instead
   - Impact: Multiple sequential scans
   - Severity: WARN/ERROR

6. **UNION Without ALL** (Low/Medium Risk)
   - UNION requires sorting; UNION ALL is often faster
   - Recommendation: Use UNION ALL if duplicates are acceptable
   - Impact: Unnecessary sorting overhead
   - Severity: INFO/WARN

7. **DISTINCT Clause** (Low Risk)
   - DISTINCT forces sorting to remove duplicates
   - Recommendation: Verify necessity; often indicates missing WHERE or GROUP BY
   - Impact: Additional sorting overhead
   - Severity: INFO

8. **GROUP BY Without ORDER BY** (Low Risk)
   - GROUP BY results are returned in unpredictable order
   - Recommendation: Add ORDER BY if specific order is needed
   - Impact: Non-deterministic result ordering
   - Severity: INFO

#### Request-Level Risks

1. **Repeated Query** (Medium Risk)
   - Same query executed 3+ times in a single request
   - Indicates missing eager loading or caching
   - Example: Fetching same user ID multiple times
   - Severity: WARN

2. **Potential N+1 Query Problem** (High Risk)
   - 5+ SELECT queries hitting ~2 tables in single request
   - Classic N+1 pattern: initial query + loop with per-item queries
   - Recommendation: Use eager loading (includes, joins) or batch fetching
   - Impact: 10-100x more queries than necessary
   - Severity: ERROR

## Configuration

### Enable/Disable Risk Analysis

```ruby
QueryGuard.configure do |config|
  # Enable query risk analysis (default: true)
  config.analyze_query_risks = true
  
  # Optional: Disable specific analyzers
  config.disable_analyzer(:query_risk)
  
  # Optional: Enable specific analyzers
  config.enable_analyzer(:query_risk)
end
```

### Risk Thresholds

The Query Risk Analyzer currently uses built-in heuristics:
- **Complex Join Threshold**: 5 tables (configurable in future versions)
- **Repeated Query Threshold**: 3 occurrences
- **N+1 Pattern Threshold**: 5+ queries on ~2 tables

Future versions will support threshold customization:

```ruby
QueryGuard.configure do |config|
  config.risk_config = {
    enable_repeated_query_detection: true,
    enable_n_plus_one_detection: true,
    complex_join_table_threshold: 5,
    repeated_query_threshold: 3,
    n_plus_one_query_threshold: 5
  }
end
```

## Usage

### Basic Usage

The analyzer is automatically registered and runs as part of the standard QueryGuard pipeline:

```ruby
QueryGuard.install!(Rails.application)
QueryGuard.configure do |config|
  config.analyze_query_risks = true
end
```

### Accessing Findings

Risk findings are returned alongside other query findings:

```ruby
# In a controller or service
context = QueryGuard::Core::Context.new
query = QueryGuard::Core::Query.new(
  sql: "SELECT * FROM users WHERE name LIKE '%john%'",
  name: "User.search",
  duration_ms: 150
)
context.add_query(query)

config = QueryGuard::Config.new
analyzer = QueryGuard::Analyzers::QueryRiskAnalyzer.new
findings = analyzer.analyze(context, config)

findings.each do |finding|
  puts "#{finding.title} (#{finding.rule_name})"
  puts "  Severity: #{finding.severity}"
  puts "  Message: #{finding.message}"
  puts "  Recommendations:"
  finding.recommendations.each { |rec| puts "    - #{rec}" }
end
```

### Finding Object Structure

Each risk finding includes:

```ruby
{
  id: "finding-uuid",                    # Unique identifier
  analyzer: :query_risk,                 # Analyzer name
  rule: :select_star,                    # Rule/pattern name
  severity: :warn,                       # Severity level
  title: "SELECT * Usage",               # Human-readable title
  description: "Selecting all columns...", # Detailed description
  message: "SELECT * detected: ...",     # Specific issue
  sql: "SELECT * FROM users",            # The query itself
  file_path: nil,                        # Caller file (when available)
  line_number: nil,                      # Caller line (when available)
  recommendations: ["Specify..."],       # Actionable advice
  metadata: {                            # Additional context
    recommendation: "...",
    impact: "...",
    pattern: :select_star
  },
  created_at: Time.now                   # When finding was created
}
```

## Examples

### Example 1: Detecting SELECT *

```ruby
context = QueryGuard::Core::Context.new
context.add_query(
  sql: "SELECT * FROM users WHERE status = 'active'",
  name: "User.active",
  duration_ms: 45
)

analyzer = QueryGuard::Analyzers::QueryRiskAnalyzer.new
findings = analyzer.analyze(context, QueryGuard::Config.new)

# Output: 1 finding
# SELECT * Usage (select_star) - WARN severity
# Recommendation: Specify only required columns explicitly
```

### Example 2: Detecting N+1 Pattern

```ruby
context = QueryGuard::Core::Context.new

# Initial query
context.add_query(sql: "SELECT id FROM orders WHERE user_id = 123", duration_ms: 10)

# Loop: 10 queries on 2 tables
10.times do |i|
  context.add_query(sql: "SELECT id FROM users WHERE id = #{i}", duration_ms: 5)
  context.add_query(sql: "SELECT total FROM order_items WHERE order_id = #{i}", duration_ms: 5)
end

analyzer = QueryGuard::Analyzers::QueryRiskAnalyzer.new
findings = analyzer.analyze(context, QueryGuard::Config.new)

# Output: 1 finding
# Potential N+1 Query Problem (potential_n_plus_one) - ERROR severity
# Recommendation: Use eager loading (includes, joins) or batch fetching
# Metadata: Detected 21 SELECT queries hitting ~2 table(s)
```

### Example 3: Complex Query with Multiple Risks

```ruby
context = QueryGuard::Core::Context.new
context.add_query(
  sql: "SELECT * FROM users WHERE name LIKE '%smith%' AND id IN (SELECT user_id FROM orders)",
  name: "User.search",
  duration_ms: 250
)

analyzer = QueryGuard::Analyzers::QueryRiskAnalyzer.new
findings = analyzer.analyze(context, QueryGuard::Config.new)

# Output: 3 findings
# 1. SELECT * Usage (select_star) - WARN
# 2. LIKE Without Index (like_without_index) - ERROR
# 3. Nested Subqueries (nested_subqueries) - WARN
```

## Integration with CI/CD

Query risk findings can be exported for CI integration:

```ruby
# Collect findings
findings = analyzer.analyze(context, config)

# Serialize to JSON
findings_json = findings.map(&:to_json_h).to_json

# Send to upstream service
client.post('/findings', findings_json)

# Filter by severity for CI gates
errors = findings.select { |f| f.severity == :error }
if errors.any?
  exit(1)  # Fail CI build
end
```

## Performance

The Query Risk Analyzer is designed for minimal overhead:

- **Per-Query Analysis**: ~1ms per detector run (6 detectors)
- **Context Analysis**: ~5ms for typical request with 50 queries
- **Total Impact**: <2% overhead on request processing

## Future Enhancements

Planned improvements:

1. **Database EXPLAIN Integration**
   - Analyze actual query plans from database
   - Detect missing indexes directly from EXPLAIN output
   - Factor in column cardinality and selectivity

2. **Configurable Thresholds**
   - User-defined risk levels per pattern
   - Custom heuristics for N+1 detection
   - Ignore patterns per application

3. **Machine Learning Integration**
   - Learn normal query patterns for your application
   - Flag anomalies in query distribution
   - Predictive performance warnings

4. **Historical Analysis**
   - Track risk trends over time
   - Identify frequently problematic queries
   - Generate performance improvement reports

5. **Remediation Suggestions**
   - Auto-suggest specific index creation commands
   - Generate refactored query suggestions
   - Recommend migration strategies

## Troubleshooting

### Analyzer Not Running

Check that it's enabled:
```ruby
config = QueryGuard::Config.new
config.analyze_query_risks  # Should be true
```

### Too Many Findings

Consider filtering by severity:
```ruby
findings = analyzer.analyze(context, config)
important_findings = findings.select { |f| f.severity == :error }
```

### False Positives

Some patterns may not always be issues:
- SELECT * in small tables may be acceptable
- Simple subqueries may not require optimization
- Repeated queries in batch operations are expected

Plan to make individual patterns configurable in future versions.

## Contributing

To add new risk detectors:

1. Create a detector class inheriting from `QueryGuard::Analysis::RiskDetector`
2. Implement the `detect(query, config)` method
3. Return array of risk hashes with: pattern, risk_level, message, metadata
4. Add tests in `spec/analysis/risk_analysis_spec.rb`
5. Update this documentation

Example:

```ruby
class CustomRiskDetector < QueryGuard::Analysis::RiskDetector
  def detect(query, config)
    sql = query.sql.upcase
    return [] unless sql.include?("DANGEROUS_PATTERN")
    
    [{
      pattern: :custom_risk,
      risk_level: :high,
      message: "Custom risk detected in query",
      metadata: {
        recommendation: "Avoid this pattern",
        impact: "Performance degradation"
      }
    }]
  end
end
```

## See Also

- [DESIGN.md](DESIGN.md) - Architecture details
- [FINDING_MODEL.md](FINDING_MODEL.md) - Finding object documentation
- [README.md](README.md) - Main project documentation
