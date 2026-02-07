# Changelog

All notable changes to QueryGuard will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - Unreleased

### Added - Major v2 Features

#### Budget System (Query SLOs)
- **Budget DSL**: Define query budgets per controller action via `config.budget.for("controller#action", count:, duration_ms:)`
- **Job Budgets**: Define budgets for background jobs via `config.budget.for_job(JobClass, count:, duration_ms:)`
- **Three Enforcement Modes**:
  - `:log` - Log warnings only (safe for production)
  - `:notify` - Call custom callback for monitoring integration
  - `:raise` - Raise exception (ideal for CI/testing)
- **Violation Callbacks**: `config.budget.on_violation` for integration with Datadog, Sentry, Honeybadger, etc.
- **Per-Environment Configuration**: Different budgets and modes per environment

#### Trace API
- **Manual Query Tracking**: `QueryGuard.trace(label, context:) { ... }` for console and code
- **Rich Reports**: Returns `[result, report]` with query count, duration, violations, fingerprints
- **Context Support**: Pass context hash for better debugging and correlation
- **Budget Integration**: Automatic budget violation checking in traces
- **Thread-Safe**: Properly manages thread-local stats

#### RSpec Integration
- **Budget Matcher**: `expect { ... }.to_not exceed_query_budget(count:, duration_ms:)`
- **Named Budget Matcher**: `expect { ... }.to_not exceed_query_budget("users#index")`
- **Helper Method**: `within_query_budget(count:, duration_ms:) { ... }` raises on violation
- **Auto-Configuration**: Automatically includes helpers when RSpec is loaded

#### Enhanced Fingerprinting
- **Advanced SQL Normalization**:
  - Removes string and numeric literals
  - Normalizes `IN (...)` lists
  - Collapses whitespace
  - Case-insensitive
- **Per-Fingerprint Statistics**:
  - Execution count
  - Total, min, max duration
  - First and last seen timestamps
- **Query Ranking APIs**:
  - `QueryGuard::Fingerprint.top_by_count(limit)` - Most frequent queries
  - `QueryGuard::Fingerprint.top_by_duration(limit)` - Highest total time
  - `QueryGuard::Fingerprint.top_by_avg_duration(limit)` - Slowest on average
- **Stats API**: `QueryGuard::Fingerprint.stats_for(fingerprint)` for detailed metrics
- **Process-Level Storage**: In-memory statistics per process

### Documentation
- **Comprehensive README**: Complete feature overview with comparisons to Datadog, Skylight, and Grafana
- **EXAMPLES.md**: Practical usage examples for all scenarios (development, testing, production)
- **MIGRATION.md**: Detailed v1 → v2 migration guide with backward compatibility notes
- **Inline Documentation**: Well-commented code throughout all modules

### Testing
- **77 Comprehensive Tests**: 100% passing test suite
  - 19 tests for Budget module
  - 21 tests for Fingerprint module
  - 19 tests for Trace module
  - 15 tests for RSpec matchers
  - 3 tests for core integration

### Backward Compatibility
- **100% Backward Compatible**: All v1 configuration options still work
- **No Breaking Changes**: Existing code continues to function
- **Gradual Adoption**: New features can be adopted incrementally

### Changed
- Enhanced `QueryGuard::Security.fingerprint` with new `QueryGuard::Fingerprint` module
- Updated `Config` class to include `budget` accessor
- Main `QueryGuard` module now delegates to `Trace.trace` for convenience

## [0.1.0] - 2025-11-02

### Added
- Initial release
- Basic query counting per request
- Slow query detection
- SELECT * statement blocking
- SQL injection detection
- Unusual query pattern detection
- Data exfiltration monitoring
- Mass assignment detection
- HTTP export to external API
- Security threat detection
- Thread-local statistics tracking
- Middleware integration
- Rails Railtie for auto-installation
- ActiveSupport::Notifications integration
- Basic configuration DSL
