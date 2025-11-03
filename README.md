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
end
```
