# QueryGuard

A **Rails-native APM layer** focused on SQL performance and schema intelligence. QueryGuard provides deep ActiveRecord integration, query budgets, schema-aware linting, and developer-friendly testing tools.

## 🎯 What Makes QueryGuard Different?

QueryGuard fills a unique niche between traditional APMs and Rails profilers:

- **vs Datadog APM**: Datadog excels at distributed tracing, logs/metrics correlation, and infrastructure monitoring, but is generic across languages. QueryGuard is **deeply Rails and ActiveRecord-aware**, providing schema intelligence and query budgets that Datadog doesn't offer.

- **vs Skylight**: Skylight is an excellent Rails profiler with request timelines, deploy tracking, and background job support. QueryGuard complements this by adding **query budgets/SLOs per endpoint**, **schema-aware linting** (missing indexes, wide scans), and **first-class test/CI support** via RSpec matchers.

- **vs Grafana**: Grafana provides powerful multi-signal visualization and metrics↔traces workflows via exemplars, but isn't Rails-specific. QueryGuard offers **Rails-native tooling** that works in development, tests, and production with minimal configuration.

**QueryGuard's Focus**: SQL + Schema + Budget enforcement + Developer UX (console, tests, CI).

## 📦 Installation

Add to your Gemfile:

```ruby
gem "query_guard"
```

Then run:

```bash
bundle install
```

## ⚙️ Configuration

Create an initializer at `config/initializers/query_guard.rb`:

```ruby
QueryGuard.configure do |config|
  # Environments where QueryGuard should be active
  config.enabled_environments = %i[development test production]

  # === Budget System (New in v2) ===
  # Define query budgets/SLOs for specific endpoints or jobs
  
  # Controller actions
  config.budget.for("users#index", count: 10, duration_ms: 500)
  config.budget.for("posts#show", count: 5, duration_ms: 200)
  config.budget.for("admin/reports#dashboard", count: 50, duration_ms: 2000)
  
  # Background jobs
  config.budget.for_job("EmailJob", count: 20, duration_ms: 1000)
  config.budget.for_job("DataExportJob", count: 100, duration_ms: 5000)
  
  # Budget enforcement mode
  config.budget.mode = :log       # :log (warn only), :notify (callback), :raise (exception)
  
  # Optional: callback for :notify mode
  config.budget.on_violation = ->(key, violation) {
    # Send to error tracker, metrics service, etc.
    Honeybadger.notify("Budget violation", context: { key: key, violation: violation })
  }

  # === Legacy Limits (Still Supported) ===
  config.max_queries_per_request = 100
  config.max_duration_ms_per_query = 100.0
  config.block_select_star = true
  
  # Ignore certain SQL patterns
  config.ignored_sql = [
    /^PRAGMA /i,
    /^BEGIN/i,
    /^COMMIT/i,
    /^SHOW /i
  ]

  # === Security Features ===
  config.enable_security = true
  config.detect_sql_injection = true
  config.detect_unusual_query_pattern = true
  config.detect_data_exfiltration = true
  config.detect_mass_assignment = true

  # === Export Configuration ===
  config.base_url = ENV["QUERY_GUARD_API_URL"]
  config.api_key = ENV["QUERY_GUARD_API_KEY"]
  config.project = "my_app"
  config.env = Rails.env
  
  # Logging
  config.raise_on_violation = false  # Set to true in CI
  config.log_prefix = "[QueryGuard]"
end
```

## 🚀 Features

### 1. Query Budgets & SLOs

Define query budgets for specific endpoints or background jobs:

```ruby
# In config/initializers/query_guard.rb
QueryGuard.configure do |config|
  # Set budgets for controller actions
  config.budget.for("users#index", count: 10, duration_ms: 500)
  config.budget.for("posts#show", count: 5, duration_ms: 200)
  
  # Set budgets for background jobs
  config.budget.for_job("EmailJob", count: 20)
  config.budget.for_job("ReportJob", count: 100, duration_ms: 5000)
  
  # Choose enforcement mode
  config.budget.mode = :log  # Options: :log, :notify, :raise
end
```

**Enforcement Modes**:

- `:log` - Logs warnings when budgets are exceeded (default, safe for production)
- `:notify` - Calls a custom callback for integration with error trackers
- `:raise` - Raises an exception (useful in test/CI environments)

**With Callbacks**:

```ruby
config.budget.mode = :notify
config.budget.on_violation = ->(key, violation) {
  # Send to your monitoring service
  Datadog::Statsd.new.increment("query_guard.budget.exceeded", tags: ["endpoint:#{key}"])
  
  # Or send to error tracker
  Sentry.capture_message("Budget exceeded", extra: { key: key, violation: violation })
}
```

### 2. Trace API (Console & Testing)

Manually trace query performance in any context:

```ruby
# In Rails console or tests
result, report = QueryGuard.trace("load active users") do
  User.where(active: true).limit(100).to_a
end

puts "Queries executed: #{report.query_count}"
puts "Total duration: #{report.total_duration_ms}ms"
puts "Violations: #{report.violations.inspect}"
puts "Queries:"
report.queries.each do |q|
  puts "  #{q[:duration_ms]}ms: #{q[:sql]}"
end
```

**With Context**:

```ruby
result, report = QueryGuard.trace("process batch", context: { batch_id: 123, user_id: 456 }) do
  Batch.find(123).process!
end

# Context is included in the report for correlation
puts report.context  # => { batch_id: 123, user_id: 456 }
```

### 3. RSpec Matchers

Test query performance in your specs:

```ruby
require "query_guard/rspec"

RSpec.describe UsersController, type: :controller do
  describe "GET #index" do
    it "stays within query budget" do
      expect {
        get :index
      }.to_not exceed_query_budget(count: 10, duration_ms: 500)
    end
    
    # Or use named budgets defined in config
    it "respects users#index budget" do
      expect {
        get :index
      }.to_not exceed_query_budget("users#index")
    end
  end
end
```

**Helper Method**:

```ruby
RSpec.describe "batch processing" do
  it "processes batch efficiently" do
    report = within_query_budget(count: 50, duration_ms: 2000) do
      Batch.process_all
    end
    
    expect(report.query_count).to be < 50
  end
end
```

### 4. SQL Fingerprinting & Statistics

Track query patterns across your application:

```ruby
# In console or background job
QueryGuard::Fingerprint.record("SELECT * FROM users WHERE id = 123", 45.2)
QueryGuard::Fingerprint.record("SELECT * FROM users WHERE id = 456", 32.1)

# Get stats for a specific fingerprint
fp = QueryGuard::Fingerprint.generate("SELECT * FROM users WHERE id = ?")
stats = QueryGuard::Fingerprint.stats_for(fp)

puts stats[:count]              # => 2
puts stats[:total_duration_ms]  # => 77.3
puts stats[:min_duration_ms]    # => 32.1
puts stats[:max_duration_ms]    # => 45.2
puts stats[:first_seen_at]
puts stats[:last_seen_at]

# Get top queries by various metrics
QueryGuard::Fingerprint.top_by_count(10)         # Most frequently executed
QueryGuard::Fingerprint.top_by_duration(10)      # Highest total time
QueryGuard::Fingerprint.top_by_avg_duration(10)  # Slowest on average
```

**Fingerprinting normalizes SQL**:
- Removes string and numeric literals
- Collapses whitespace
- Normalizes `IN (...)` lists
- Returns consistent SHA1 hash

```ruby
# These all produce the same fingerprint:
QueryGuard::Fingerprint.generate("SELECT * FROM users WHERE id = 1")
QueryGuard::Fingerprint.generate("SELECT * FROM users WHERE id = 999")
QueryGuard::Fingerprint.generate("SELECT  *  FROM users WHERE id = 42")
# All normalize to: "select * from users where id = ?"
```

### 5. Security Features (Existing)

QueryGuard includes built-in security detection:

- **SQL Injection Detection**: Flags suspicious patterns (OR 1=1, UNION SELECT, etc.)
- **Unusual Query Patterns**: Rate limiting per actor (IP/user)
- **Data Exfiltration**: Monitors large responses and suspicious endpoints
- **Mass Assignment**: Detects unpermitted parameters

```ruby
config.enable_security = true
config.detect_sql_injection = true
config.detect_unusual_query_pattern = true
config.max_queries_per_minute_per_actor = 300

# Custom actor resolver
config.actor_resolver = ->(env) {
  env["warden"].user&.id || env["action_dispatch.remote_ip"]
}
```

### 6. Export & Monitoring

Export query data to external services:

```ruby
config.base_url = "https://your-monitoring-service.com"
config.api_key = ENV["MONITORING_API_KEY"]
config.project = "my_rails_app"
config.env = Rails.env
config.export_mode = :async  # Don't block requests
```

Exported data includes:
- Query statements with fingerprints
- Durations and timestamps
- Budget violations
- Security threat events
- Request context (controller, action, user, etc.)

## 📊 Use Cases

### Development

```ruby
# In Rails console
result, report = QueryGuard.trace("diagnose N+1") do
  Post.limit(10).each { |post| post.comments.to_a }
end

puts "Queries: #{report.query_count}"  # Spot N+1 problems immediately
report.queries.each { |q| puts q[:sql] }
```

### Testing (CI)

```ruby
# spec/support/query_guard.rb
RSpec.configure do |config|
  config.around(:each, :query_budget) do |example|
    metadata = example.metadata
    budget = metadata[:query_budget]
    
    expect {
      example.run
    }.to_not exceed_query_budget(**budget)
  end
end

# spec/controllers/users_controller_spec.rb
RSpec.describe UsersController do
  describe "GET #index", :query_budget, query_budget: { count: 5, duration_ms: 200 } do
    it "loads users" do
      get :index
      expect(response).to be_successful
    end
  end
end
```

### Production Monitoring

```ruby
# config/initializers/query_guard.rb
QueryGuard.configure do |config|
  config.enabled_environments = [:production]
  config.budget.mode = :notify
  
  config.budget.for("api/v1/users#index", count: 10, duration_ms: 100)
  config.budget.for("api/v1/posts#feed", count: 15, duration_ms: 150)
  
  config.budget.on_violation = ->(key, violation) {
    # Alert when budgets exceeded in production
    Datadog::Statsd.new.increment("query.budget.exceeded", tags: [
      "endpoint:#{key}",
      "type:#{violation[:type]}"
    ])
  }
end
```

## 🔧 API Reference

### QueryGuard.configure

Configure QueryGuard settings. See Configuration section above.

### QueryGuard.trace(label, context: {}, &block)

Trace a block of code and capture query statistics.

**Arguments**:
- `label` (String): Descriptive label for the trace
- `context` (Hash): Additional context (user_id, batch_id, etc.)
- `&block`: Code to trace

**Returns**: `[result, report]` tuple

### QueryGuard::Budget

**Methods**:
- `.for(key, **limits)`: Define budget for controller action
- `.for_job(job, **limits)`: Define budget for background job
- `.mode=`: Set enforcement mode (`:log`, `:notify`, `:raise`)
- `.on_violation=`: Set callback for `:notify` mode

### QueryGuard::Fingerprint

**Methods**:
- `.generate(sql)`: Generate fingerprint for SQL
- `.normalize(sql)`: Normalize SQL query
- `.record(sql, duration_ms)`: Record query execution
- `.stats_for(fingerprint)`: Get stats for fingerprint
- `.top_by_count(limit)`: Top queries by count
- `.top_by_duration(limit)`: Top queries by total duration
- `.top_by_avg_duration(limit)`: Top queries by average duration
- `.reset!`: Clear all stats

### RSpec Matchers

```ruby
require "query_guard/rspec"

expect { code }.to_not exceed_query_budget(count: 10)
expect { code }.to_not exceed_query_budget(count: 10, duration_ms: 500)
expect { code }.to_not exceed_query_budget("users#index")

report = within_query_budget(count: 10) { code }
```

## 🧪 Testing

Run the test suite:

```bash
bundle exec rspec
```

## 📄 License

MIT License. See [LICENSE.txt](LICENSE.txt) for details.

## 🙏 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Write tests for your changes
4. Submit a pull request

## 📮 Support

- Issues: [GitHub Issues](https://github.com/Chitradevi36/query_guard/issues)
- Documentation: This README
- Example Rails App: [Coming soon]

---

Built with ❤️ to make Rails query performance monitoring delightful.

