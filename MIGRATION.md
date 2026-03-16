# Migration Guide: QueryGuard v1 to v2

This guide helps you upgrade from QueryGuard v1 to v2, which introduces significant new features while maintaining backward compatibility.

## What's New in v2?

- ✅ **Budget System**: Define query budgets/SLOs per endpoint or background job
- ✅ **Trace API**: Manual query tracking in console, tests, and code
- ✅ **RSpec Matchers**: First-class testing support with custom matchers
- ✅ **Enhanced Fingerprinting**: Advanced SQL normalization and per-fingerprint statistics
- ✅ **Better Developer UX**: More tools for development and debugging

## Breaking Changes

**Good news**: There are **NO breaking changes**! v2 is fully backward compatible with v1.

All your existing configuration will continue to work:
- `config.max_queries_per_request`
- `config.max_duration_ms_per_query`
- `config.block_select_star`
- `config.raise_on_violation`
- Security features
- Export configuration

## Migration Steps

### Step 1: Update Your Gemfile

```ruby
# Gemfile
gem "query_guard"  # Will pull v2 when released
```

Run:
```bash
bundle update query_guard
```

### Step 2: Review Your Configuration

Your existing configuration still works! But you can enhance it with new v2 features.

**Before (v1)**:
```ruby
# config/initializers/query_guard.rb
QueryGuard.configure do |config|
  config.enabled_environments = %i[development test]
  config.max_queries_per_request = 100
  config.max_duration_ms_per_query = 100.0
  config.raise_on_violation = false
end
```

**After (v2 - Enhanced)**:
```ruby
QueryGuard.configure do |config|
  # All v1 settings still work
  config.enabled_environments = %i[development test production]
  config.max_queries_per_request = 100
  config.max_duration_ms_per_query = 100.0
  
  # NEW: Add specific budgets per endpoint
  config.budget.for("users#index", count: 10, duration_ms: 500)
  config.budget.for("posts#show", count: 5, duration_ms: 200)
  config.budget.for("admin/reports#dashboard", count: 50, duration_ms: 2000)
  
  # NEW: Add budgets for background jobs
  config.budget.for_job("EmailJob", count: 20)
  config.budget.for_job("DataExportJob", count: 100, duration_ms: 5000)
  
  # NEW: Configure budget enforcement
  config.budget.mode = :log  # :log, :notify, or :raise
  
  # Optional: Set up violation callback for monitoring
  config.budget.on_violation = ->(key, violation) {
    # Report to your monitoring service
    Datadog::Statsd.new.increment("query_guard.budget.exceeded")
  }
end
```

### Step 3: Add RSpec Support (Optional)

If you use RSpec, add the query budget matchers to your test suite.

**Add to `spec/rails_helper.rb` or `spec/spec_helper.rb`**:
```ruby
require "query_guard/rspec"
```

**Then use in your specs**:
```ruby
RSpec.describe UsersController, type: :controller do
  describe "GET #index" do
    it "stays within query budget" do
      expect {
        get :index
      }.to_not exceed_query_budget(count: 5, duration_ms: 100)
    end
  end
end
```

### Step 4: Use Trace API for Debugging (Optional)

In development or console sessions, use the new trace API:

```ruby
# Rails console
result, report = QueryGuard.trace("debug N+1") do
  Post.limit(10).each { |post| post.comments.count }
end

puts "Queries: #{report.query_count}"
puts "Duration: #{report.total_duration_ms}ms"
```

## Feature-by-Feature Migration

### Query Counting (v1 → v2)

**v1 Approach**: Global limit via `max_queries_per_request`
```ruby
config.max_queries_per_request = 100  # Applies to all requests
```

**v2 Enhancement**: Per-endpoint budgets (more granular)
```ruby
config.max_queries_per_request = 100  # Still works as fallback

# But now you can be more specific:
config.budget.for("users#index", count: 10)       # Stricter for simple endpoint
config.budget.for("reports#dashboard", count: 50)  # More lenient for complex page
```

**Recommendation**: Keep `max_queries_per_request` as a safety net, add specific budgets for critical endpoints.

---

### Slow Query Detection (v1 → v2)

**v1 Approach**: Global threshold via `max_duration_ms_per_query`
```ruby
config.max_duration_ms_per_query = 100.0  # Any query over 100ms is flagged
```

**v2 Enhancement**: Total duration budgets per endpoint
```ruby
config.max_duration_ms_per_query = 100.0  # Still works for individual queries

# New: Budget total duration for entire request
config.budget.for("users#index", duration_ms: 500)  # All queries combined
```

**Recommendation**: Use both - `max_duration_ms_per_query` catches individual slow queries, `duration_ms` budget catches cumulative time.

---

### Violation Handling (v1 → v2)

**v1 Approach**: Binary setting
```ruby
config.raise_on_violation = false  # Just log
# OR
config.raise_on_violation = true   # Raise exception
```

**v2 Enhancement**: Three-mode system with callbacks
```ruby
# Still works for global violations:
config.raise_on_violation = false

# New: Per-budget enforcement modes
config.budget.mode = :log     # Just log (default)
# OR
config.budget.mode = :notify  # Call custom callback
config.budget.on_violation = ->(key, v) { 
  Sentry.capture_message("Budget exceeded: #{key}")
}
# OR
config.budget.mode = :raise   # Raise exception
```

**Recommendation**: 
- Development: Use `:log` mode
- Production: Use `:notify` mode with monitoring integration
- CI/Testing: Use `:raise` mode to fail tests on violations

---

### Testing (v1 → v2)

**v1 Approach**: Manual inspection
```ruby
# No built-in testing support
it "doesn't execute too many queries" do
  expect {
    get :index
  }.to perform_queries_below(10)  # Custom helper needed
end
```

**v2 Enhancement**: Built-in RSpec matchers
```ruby
require "query_guard/rspec"

it "stays within budget" do
  expect {
    get :index
  }.to_not exceed_query_budget(count: 10)
end

# Or use named budgets from config
it "respects defined budget" do
  expect {
    get :index
  }.to_not exceed_query_budget("users#index")
end
```

---

### Console Debugging (v1 → v2)

**v1 Approach**: No built-in support, rely on Rails QueryLog or manual counting

**v2 Enhancement**: Trace API
```ruby
# In Rails console
result, report = QueryGuard.trace("investigate slow endpoint") do
  User.includes(:posts).where(active: true).limit(100).to_a
end

puts "Executed #{report.query_count} queries"
puts "Total time: #{report.total_duration_ms}ms"
report.queries.each { |q| puts "  #{q[:duration_ms]}ms: #{q[:sql]}" }
```

---

## Recommended v2 Setup

Here's a recommended configuration that leverages v2 features while keeping v1 safety nets:

```ruby
QueryGuard.configure do |config|
  # Environments
  config.enabled_environments = %i[development test staging production]
  
  # === V1 Safety Nets (Global Limits) ===
  config.max_queries_per_request = 200      # Catch extreme cases
  config.max_duration_ms_per_query = 1000   # Flag very slow individual queries
  config.block_select_star = false          # Allow SELECT * but track it
  
  # === V2 Budget System (Per-Endpoint Limits) ===
  # API endpoints - strict
  config.budget.for("api/v1/users#index", count: 10, duration_ms: 100)
  config.budget.for("api/v1/posts#show", count: 5, duration_ms: 50)
  
  # Admin pages - more lenient
  config.budget.for("admin/reports#dashboard", count: 50, duration_ms: 2000)
  config.budget.for("admin/users#index", count: 30, duration_ms: 1000)
  
  # Background jobs
  config.budget.for_job("EmailJob", count: 20, duration_ms: 5000)
  config.budget.for_job("ReportGenerationJob", count: 100, duration_ms: 30000)
  
  # === Environment-Specific Budget Modes ===
  case Rails.env.to_sym
  when :development
    config.budget.mode = :log
    config.raise_on_violation = false
  when :test
    config.budget.mode = :raise  # Fail tests on violations
    config.raise_on_violation = true
  when :staging
    config.budget.mode = :notify
    config.budget.on_violation = ->(key, v) {
      Rails.logger.warn("Budget exceeded: #{key} - #{v.inspect}")
    }
  when :production
    config.budget.mode = :notify
    config.budget.on_violation = ->(key, v) {
      # Report to monitoring
      Datadog::Statsd.new.increment("queryguard.budget.exceeded",
        tags: ["endpoint:#{key}", "type:#{v[:type]}"])
    }
  end
  
  # === Security (V1 Features) ===
  config.enable_security = true
  config.detect_sql_injection = true
  config.detect_unusual_query_pattern = true
  config.detect_data_exfiltration = true
  
  # === Export (V1 Features) ===
  if ENV["QUERY_GUARD_API_URL"]
    config.base_url = ENV["QUERY_GUARD_API_URL"]
    config.api_key = ENV["QUERY_GUARD_API_KEY"]
    config.project = Rails.application.class.module_parent_name.downcase
    config.env = Rails.env
  end
end
```

## Testing Your Migration

After upgrading, test your setup:

### 1. In Development Console

```ruby
rails console

# Test trace API
result, report = QueryGuard.trace("test") do
  User.first
end

puts report.query_count  # Should show 1
```

### 2. In RSpec

```ruby
# spec/controllers/users_controller_spec.rb
require "rails_helper"

RSpec.describe UsersController do
  it "loads index within budget" do
    expect {
      get :index
    }.to_not exceed_query_budget(count: 20)  # Generous for first test
  end
end
```

### 3. Verify Logging

Start your Rails server and trigger a request. You should see QueryGuard logs:

```
[QueryGuard] queries=5 total_ms=45.23 resp_bytes=1234
```

If budgets are exceeded and mode is `:log`:
```
[QueryGuard::Budget] users#index: Query count exceeded (15 > 10)
```

## Rollback Plan

If you need to rollback to v1 behavior:

1. Remove budget configurations:
```ruby
# Comment out or remove:
# config.budget.for(...)
# config.budget.mode = ...
```

2. Keep only v1 settings:
```ruby
config.max_queries_per_request = 100
config.max_duration_ms_per_query = 100.0
config.raise_on_violation = false
```

3. Or pin to v1 in Gemfile (when versions are released):
```ruby
gem "query_guard", "~> 1.0"
```

## Support

If you encounter issues during migration:

1. Check that all v1 configuration still works
2. Review the [Examples](EXAMPLES.md) for usage patterns
3. Open an issue on [GitHub](https://github.com/Chitradevi36/query_guard/issues)

## Summary

✅ **No Breaking Changes** - v1 config still works  
✅ **Gradual Adoption** - Add v2 features incrementally  
✅ **Better Granularity** - Per-endpoint budgets vs global limits  
✅ **Enhanced Testing** - Built-in RSpec matchers  
✅ **Better Debugging** - Trace API for console and code  

The migration is designed to be **safe, gradual, and backward-compatible**. You can adopt v2 features at your own pace!
