# QueryGuard v2 - Usage Examples

This file contains practical examples for using QueryGuard v2 in various scenarios.

## Table of Contents

1. [Basic Configuration](#basic-configuration)
2. [Development Usage](#development-usage)
3. [Testing with RSpec](#testing-with-rspec)
4. [Production Monitoring](#production-monitoring)
5. [Advanced Scenarios](#advanced-scenarios)

---

## Basic Configuration

### Minimal Setup (Development Only)

```ruby
# config/initializers/query_guard.rb
QueryGuard.configure do |config|
  config.enabled_environments = [:development]
  
  # Set basic budgets
  config.budget.for("users#index", count: 10)
  config.budget.for("posts#show", count: 5)
end
```

### Full Setup (All Environments)

```ruby
QueryGuard.configure do |config|
  config.enabled_environments = %i[development test staging production]
  
  # Controller budgets
  config.budget.for("api/v1/users#index", count: 10, duration_ms: 100)
  config.budget.for("api/v1/posts#feed", count: 15, duration_ms: 150)
  config.budget.for("admin/reports#dashboard", count: 50, duration_ms: 2000)
  
  # Job budgets
  config.budget.for_job("EmailJob", count: 20, duration_ms: 1000)
  config.budget.for_job("DataExportJob", count: 100, duration_ms: 5000)
  
  # Environment-specific modes
  case Rails.env
  when "development", "test"
    config.budget.mode = :log
  when "staging"
    config.budget.mode = :notify
    config.budget.on_violation = ->(key, violation) {
      Rails.logger.warn("Budget exceeded: #{key} - #{violation.inspect}")
    }
  when "production"
    config.budget.mode = :notify
    config.budget.on_violation = ->(key, violation) {
      # Report to monitoring service
      Datadog::Statsd.new.increment("queryguard.budget.exceeded", 
        tags: ["endpoint:#{key}", "type:#{violation[:type]}"])
    }
  end
  
  # Security settings
  config.enable_security = true
  config.detect_sql_injection = true
  
  # Export configuration
  config.base_url = ENV["QUERY_GUARD_API_URL"]
  config.api_key = ENV["QUERY_GUARD_API_KEY"]
  config.project = Rails.application.class.module_parent_name.downcase
end
```

---

## Development Usage

### Console Debugging

```ruby
# Start Rails console
rails console

# Trace a specific operation
result, report = QueryGuard.trace("load users with posts") do
  User.includes(:posts).limit(10).to_a
end

puts "Executed #{report.query_count} queries in #{report.total_duration_ms.round(2)}ms"

report.queries.each do |q|
  puts "  [#{q[:duration_ms].round(2)}ms] #{q[:sql]}"
end

# Check for N+1 problems
result, report = QueryGuard.trace("check N+1") do
  Post.limit(5).map { |post| post.comments.count }
end

if report.query_count > 6  # 1 for posts + 5 for individual counts
  puts "⚠️  Potential N+1 detected! #{report.query_count} queries executed"
end

# Analyze fingerprints
QueryGuard::Fingerprint.top_by_count(10).each do |fp, stats|
  puts "#{stats[:count]}x - avg #{(stats[:total_duration_ms] / stats[:count]).round(2)}ms"
end
```

### Debugging Slow Endpoints

```ruby
# In a controller, temporarily add tracing
class UsersController < ApplicationController
  def index
    result, report = QueryGuard.trace("users#index debug") do
      @users = User.includes(:posts, :comments)
                   .where(active: true)
                   .page(params[:page])
    end
    
    if Rails.env.development?
      Rails.logger.debug "Query Report: #{report.to_h}"
    end
    
    render json: @users
  end
end
```

---

## Testing with RSpec

### Basic Usage

```ruby
require "rails_helper"
require "query_guard/rspec"

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

### Using Named Budgets

```ruby
# config/initializers/query_guard.rb
QueryGuard.configure do |config|
  config.budget.for("users#index", count: 5, duration_ms: 100)
  config.budget.for("posts#show", count: 3, duration_ms: 50)
end

# spec/controllers/users_controller_spec.rb
RSpec.describe UsersController do
  describe "GET #index" do
    it "respects query budget" do
      expect {
        get :index
      }.to_not exceed_query_budget("users#index")
    end
  end
end
```

### Shared Examples

```ruby
# spec/support/shared_examples/query_budgets.rb
RSpec.shared_examples "respects query budget" do |action, budget|
  it "stays within budget for #{action}" do
    expect {
      perform_action(action)
    }.to_not exceed_query_budget(**budget)
  end
end

# Usage
RSpec.describe Api::V1::UsersController do
  def perform_action(action)
    send(:get, action)
  end
  
  it_behaves_like "respects query budget", :index, { count: 5, duration_ms: 100 }
  it_behaves_like "respects query budget", :show, { count: 2, duration_ms: 50 }
end
```

### Integration Tests

```ruby
RSpec.describe "User Registration Flow", type: :request do
  it "completes registration efficiently" do
    report = within_query_budget(count: 20, duration_ms: 500) do
      post "/api/v1/users", params: {
        user: { email: "test@example.com", password: "password123" }
      }
      
      expect(response).to have_http_status(:created)
      
      user = User.last
      expect(user.email).to eq("test@example.com")
    end
    
    # Can inspect report after
    expect(report.query_count).to be < 15
  end
end
```

### Background Job Testing

```ruby
RSpec.describe EmailJob do
  it "sends email within budget" do
    expect {
      EmailJob.perform_now(user_id: user.id)
    }.to_not exceed_query_budget(count: 10, duration_ms: 500)
  end
end
```

---

## Production Monitoring

### Integration with Datadog

```ruby
# config/initializers/query_guard.rb
QueryGuard.configure do |config|
  config.budget.mode = :notify
  config.budget.on_violation = ->(key, violation) {
    statsd = Datadog::Statsd.new
    
    # Send metric
    statsd.increment("query_guard.budget.exceeded", tags: [
      "endpoint:#{key}",
      "type:#{violation[:type]}",
      "env:#{Rails.env}"
    ])
    
    # Send detailed event
    statsd.event(
      "QueryGuard Budget Exceeded",
      "Budget exceeded for #{key}: #{violation.inspect}",
      alert_type: "warning",
      tags: ["endpoint:#{key}"]
    )
  }
end
```

### Integration with Sentry

```ruby
config.budget.on_violation = ->(key, violation) {
  Sentry.capture_message("QueryGuard budget exceeded", level: :warning, extra: {
    endpoint: key,
    violation: violation,
    environment: Rails.env
  })
}
```

### Integration with Honeybadger

```ruby
config.budget.on_violation = ->(key, violation) {
  Honeybadger.notify("QueryGuard budget exceeded", context: {
    endpoint: key,
    violation_type: violation[:type],
    actual: violation[:actual],
    limit: violation[:limit]
  })
}
```

### Custom Slack Notifications

```ruby
config.budget.on_violation = ->(key, violation) {
  next unless Rails.env.production?
  
  slack_webhook = ENV["SLACK_WEBHOOK_URL"]
  next unless slack_webhook
  
  message = {
    text: "⚠️ QueryGuard Budget Exceeded",
    attachments: [{
      color: "warning",
      fields: [
        { title: "Endpoint", value: key, short: true },
        { title: "Type", value: violation[:type], short: true },
        { title: "Actual", value: violation[:actual].to_s, short: true },
        { title: "Limit", value: violation[:limit].to_s, short: true }
      ]
    }]
  }
  
  # Send async to avoid blocking request
  Thread.new {
    HTTParty.post(slack_webhook, body: message.to_json, headers: { "Content-Type" => "application/json" })
  }
}
```

---

## Advanced Scenarios

### Per-Environment Budget Overrides

```ruby
QueryGuard.configure do |config|
  # Base budgets
  config.budget.for("users#index", count: 10, duration_ms: 500)
  
  # Stricter in production
  if Rails.env.production?
    config.budget.for("users#index", count: 5, duration_ms: 200)
  end
  
  # More lenient in development
  if Rails.env.development?
    config.budget.for("users#index", count: 50, duration_ms: 5000)
  end
end
```

### Multi-Tenant Budgets

```ruby
# In a concern or base controller
module QueryBudgetTracking
  extend ActiveSupport::Concern
  
  included do
    around_action :track_query_budget
  end
  
  private
  
  def track_query_budget
    tenant = current_tenant
    action_key = "#{controller_name}##{action_name}"
    
    _, report = QueryGuard.trace(action_key, context: { tenant: tenant.id }) do
      yield
    end
    
    # Custom handling per tenant tier
    if tenant.premium? && report.has_violations?
      Rails.logger.warn("Premium tenant #{tenant.id} hit budget on #{action_key}")
    end
  end
end
```

### Conditional Budget Enforcement

```ruby
class ReportsController < ApplicationController
  def dashboard
    # Allow higher budget for admin users
    budget = current_user.admin? ? { count: 100, duration_ms: 5000 } : { count: 20, duration_ms: 1000 }
    
    report = within_query_budget(**budget) do
      @reports = Report.includes(:user, :metrics)
                      .where(user: current_user)
                      .page(params[:page])
    end
  rescue QueryGuard::Budget::Violation => e
    # Handle gracefully
    @reports = []
    flash[:error] = "Report generation is taking too long. Please try again later."
  end
end
```

### Fingerprint Analysis Task

```ruby
# lib/tasks/query_guard.rake
namespace :query_guard do
  desc "Analyze query patterns"
  task analyze: :environment do
    puts "Top 10 Most Frequent Queries:"
    puts "-" * 80
    
    QueryGuard::Fingerprint.top_by_count(10).each_with_index do |(fp, stats), idx|
      avg_duration = (stats[:total_duration_ms] / stats[:count]).round(2)
      puts "#{idx + 1}. Count: #{stats[:count]}, Avg: #{avg_duration}ms"
      puts "   FP: #{fp}"
      puts
    end
    
    puts "\nTop 10 Slowest Queries (by total time):"
    puts "-" * 80
    
    QueryGuard::Fingerprint.top_by_duration(10).each_with_index do |(fp, stats), idx|
      avg_duration = (stats[:total_duration_ms] / stats[:count]).round(2)
      puts "#{idx + 1}. Total: #{stats[:total_duration_ms].round(2)}ms, Count: #{stats[:count]}, Avg: #{avg_duration}ms"
      puts "   FP: #{fp}"
      puts
    end
  end
end
```

---

## Tips & Best Practices

1. **Start in Development**: Test budgets in development before enforcing in production
2. **Use `:log` mode first**: Gather data on actual query patterns
3. **Gradual Rollout**: Start with `:notify` mode in production, move to `:raise` in CI
4. **Monitor Violations**: Set up alerts for production budget violations
5. **Review Fingerprints**: Regularly analyze top queries to find optimization opportunities
6. **Test in CI**: Use RSpec matchers to catch regressions early
7. **Context is Key**: Always include relevant context in traces for better debugging
