# QueryGuard: Migration Safety for Rails

**Catch risky database changes before they reach production.**

QueryGuard automatically analyzes your Rails migrations in CI to detect safety issues, preventing schema problems from entering your codebase.

## What QueryGuard Does

**v1.0 Focus: Migration Safety**

QueryGuard runs in your CI pipeline to analyze database migrations for common risk patterns:

- **Risky Migrations**: Detects potentially unsafe operations like adding non-nullable columns without defaults
- **Missing Rollback**: Identifies migrations that can't be safely rolled back
- **Performance Issues**: Flags migrations that might lock large tables or cause long-running locks
- **Schema Consistency**: Warns about migrations that contradict your current schema

## Installation

Add QueryGuard to your Gemfile:

```ruby
group :development, :test do
  gem 'query_guard'
end
```

Then install and generate the initializer:

```bash
bundle install
bundle exec rails generate query_guard:install
```

This creates `config/initializers/query_guard.rb` with essential configuration.

## Configuration

The default configuration works for most Rails applications. Edit `config/initializers/query_guard.rb` to customize:

```ruby
QueryGuard.configure do |config|
  # Directory where migrations live (default: db/migrate)
  config.migrations_directory = 'db/migrate'

  # Environments to analyze (default: [:development, :test])
  config.enabled_environments = [:development, :test]

  # Max queries to check per request (prevent timeouts)
  config.max_queries_per_request = 100

  # Max query duration in ms before flagging as slow
  config.max_duration_ms_per_query = 5000
end
```

## Using QueryGuard

### In CI (Recommended)

Add to your CI workflow to check migrations automatically:

```yaml
# .github/workflows/db-safety.yml
name: Database Safety
on: [pull_request]

jobs:
  analyze:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:14
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        env:
          POSTGRES_PASSWORD: postgres

    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.3.0
          bundler-cache: true

      - name: Analyze migrations
        run: bundle exec queryguard analyze
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost/test_db
```

### Locally

```bash
# Analyze migrations in your current environment
bundle exec queryguard analyze

# Get JSON output for integration with CI dashboards
bundle exec queryguard analyze --format json
```

## JSON Output

QueryGuard can output analysis results as JSON for integration with CI dashboards, security tools, or custom workflows:

```bash
bundle exec queryguard analyze --format json
```

### JSON Schema

```json
{
  "status": "success",
  "findings": [
    {
      "type": "risky_migration",
      "severity": "high",
      "message": "Adding non-nullable column without default",
      "file": "db/migrate/20240101120000_add_user_status.rb",
      "line": 4,
      "context": {
        "migration_name": "AddUserStatus",
        "environment": "test"
      }
    }
  ],
  "metadata": {
    "environment": "test",
    "database": "postgresql",
    "schema_version": "20240101120000"
  }
}
```

## What's Coming Next

**v2.0 (Future)**
- Query analysis for N+1 problems and missing indexes
- Live application query monitoring
- Performance recommendations based on actual query patterns
- SaaS dashboard integration

**v1.0** focuses exclusively on migration safety because:
1. Migrations are deterministic and analyzable in CI
2. Migration problems are expensive to fix in production
3. This gives you immediate, measurable value

For query monitoring in your application, see QueryGuard's query analysis (coming v2.0) or integrate with tools like:
- [New Relic APM](https://newrelic.com)
- [DataDog APM](https://www.datadoghq.com)
- [Sentry Performance](https://sentry.io)

## Development

To set up the development environment:

```bash
git clone https://github.com/yourusername/query_guard.git
cd query_guard
bundle install
bundle exec rake spec
```

All 186+ tests should pass. QueryGuard maintains 100% test coverage for core analysis logic.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

## License

MIT License - See [LICENSE.txt](LICENSE.txt) for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/query_guard/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/query_guard/discussions)
- **Docs**: See [INDEX.md](INDEX.md) for complete documentation

---

### Why QueryGuard?

Database migrations are a critical part of your deployment pipeline. A single unsafe migration can:
- Lock production tables for hours
- Cause deployment failures requiring emergency rollbacks
- Add months of technical debt to your schema

QueryGuard catches these issues in CI, before they reach production.

**Stop deploying database surprises.** Start using QueryGuard.

