# query_guard

Guardrails for ActiveRecord queries per request: maximum query count, slow query flagging, and optional `SELECT *` blocking.

## Installation

Add to your Gemfile:

```ruby
gem "query_guard"
```

## ⚙️ Configuration File

To enable and configure `QueryGuard` in your Rails application,  
you need to create an initializer file with the configuration options below.

---

### 1️⃣ Create the configuration file

Run this command inside your Rails app:

```bash
touch config/initializers/query_guard.rb
```

### 2️⃣ Add the following code inside that file:

```ruby
# config/initializers/query_guard.rb

# Configure QueryGuard settings
QueryGuard.configure do |config|
  # Environments where QueryGuard should be active
  # By default: [:development, :test]
  config.enabled_environments = %i[development test]

  # Maximum number of SQL queries allowed per request
  # Use nil to disable this limit
  config.max_queries_per_request = 100

  # Maximum duration (milliseconds) for a single SQL query
  # Logs as a slow query if exceeded
  config.max_duration_ms_per_query = 100.0

  # Whether to flag or block SELECT * statements
  config.block_select_star = true

  # Ignore certain SQL patterns (e.g., schema and transaction queries)
  config.ignored_sql = [
    /^PRAGMA /i,  # SQLite schema queries
    /^BEGIN/i,
    /^COMMIT/i
  ]

  # Raise exception on violation instead of just logging
  config.raise_on_violation = false

  # Prefix for log messages in Rails logs
  config.log_prefix = "[QueryGuard]"

  # Enable Query Risk Analysis (NEW in v0.5.0)
  # Analyzes SQL patterns for performance and safety risks
  config.analyze_query_risks = true
end
```

## Features

### Core Query Analysis
- ✅ **Query Count Tracking**: Monitor total queries per request
- ✅ **Slow Query Detection**: Flag queries exceeding duration threshold
- ✅ **SELECT * Blocking**: Optional prevention of wildcard column selection

### Advanced Risk Analysis
- ✅ **Pattern Detection**: SELECT *, LIKE without index, complex joins, subqueries
- ✅ **Request-Level Analysis**: Detect N+1 problems and repeated queries  
- ✅ **Structured Findings**: Rich results with recommendations and severity levels
- ✅ **Extensible**: Add custom analyzers and detectors

## Query Risk Analyzer

QueryGuard includes an advanced SQL pattern analyzer that detects common performance anti-patterns:

### Detected Patterns

**Query-Level Risks:**
- SELECT * Usage - Unnecessary column selection
- LIKE Without Index - Pattern matching on unindexed columns
- Functions in JOINs - Prevents index usage
- Complex Multi-Table Joins - 5+ table joins
- Nested Subqueries - Missing JOIN or CTE optimization

**Request-Level Risks:**
- Repeated Queries - Same query 3+ times in one request
- N+1 Patterns - 5+ SELECTs on ~2 tables in one request

## Documentation

- [Risk Analysis Guide](RISK_ANALYSIS.md) - Complete patterns, configuration, and examples
- [Finding Model Reference](FINDING_MODEL.md) - Structured result objects
- [Architecture & Design](DESIGN.md) - System design and patterns
- [Phase 4 Summary](PHASE_4_SUMMARY.md) - Implementation details

## Version History

### v0.5.0
- Core analyzer refactoring with modular rule system
- Finding model with rich attributes
- Analyzer registry pattern

### v0.5.1 (Phase 4)
- Query Risk Analyzer for SQL pattern detection
- 6 concrete pattern detectors
- Request-level N+1 and repeated query detection
- 93+ comprehensive tests
- Complete risk analysis documentation
