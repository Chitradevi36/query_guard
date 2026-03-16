# Configuration for QueryGuard Demo

## Database Setup

### PostgreSQL (Recommended for Demo)

```bash
# Create demo database
createdb queryguard_demo

# Or via Rails
export DATABASE_URL="postgres://postgres:password@localhost:5432/queryguard_demo"
bundle exec rake db:create
```

### SQLite (Simplest for Quick Testing)

```bash
export DATABASE_URL="sqlite3:db/demo.sqlite3"
bundle exec rake db:create
```

## QueryGuard Configuration

### In config/initializers/query_guard.rb

```ruby
QueryGuard.configure do |config|
  # Enable in development and test
  config.enabled_environments = %i[development test]

  # Set thresholds for demo
  config.max_queries_per_request = 200
  config.max_duration_ms_per_query = 500.0

  # Flag SELECT * usage
  config.block_select_star = false  # Log for demo, don't block

  # Log prefix for visibility
  config.log_prefix = "[DEMO] QueryGuard"
end
```

## Running the Demo

### Basic Analysis

```bash
# Analyze all migrations
bundle exec queryguard analyze db/migrate

# Get structured JSON output
bundle exec queryguard analyze db/migrate --format json

# Verbose analysis with recommendations
bundle exec queryguard analyze db/migrate --verbose
```

### Check with Thresholds

```bash
# Check for critical issues (should fail - has CRITICAL finding)
bundle exec queryguard check db/migrate --threshold critical
# Exit code: 1 (has critical findings)

# Check for warnings (should fail - has WARN findings)
bundle exec queryguard check db/migrate --threshold warn
# Exit code: 1 (has warning findings)

# Check for info (should pass - no CRITICAL or ERROR)
bundle exec queryguard check db/migrate --threshold info
# Exit code: 0 (all findings below threshold)
```

## Expected Output Patterns

### Summary Output

```
✓ analyzed 6 migrations
✓ analyzed 125 queries
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔴 CRITICAL: 1 finding
🟡 WARN:     3 findings
🟢 INFO:     2 findings
```

### JSON Structure

```json
{
  "summary": {
    "total_findings": 6,
    "by_severity": {
      "critical": 1,
      "error": 0,
      "warn": 3,
      "info": 2
    }
  },
  "findings": [
    {
      "id": "abc123",
      "rule": "remove_column_without_backfill",
      "severity": "critical",
      "title": "Removing column detected",
      "file_path": "db/migrate/20240104000004_remove_phone_from_users.rb",
      "line_number": 7,
      "recommendation": ["Archive data first", "Use separate migration"]
    }
  ]
}
```

## Demo Scenarios

### Scenario 1: Show What QueryGuard Catches

```bash
# Run basic analysis
bundle exec queryguard analyze db/migrate

# Point out:
# - 1 CRITICAL: data loss risk from removing column
# - 3 WARN: performance and reliability risks
# - 2 INFO: clean migrations passed validation
```

### Scenario 2: CI Integration Test

```bash
# Simulate CI check (would pass with warning threshold)
bundle exec queryguard check db/migrate --threshold warn
# Returns exit code 1 (fails due to warnings in CI)

# Show remediation
# "Developer must fix 3 warnings before merging"
```

### Scenario 3: JSON Report Generation

```bash
# Generate report for dashboard
bundle exec queryguard analyze db/migrate --format json > report.json

# Show that it includes:
# - Git metadata (if in repo)
# - CI metadata (if running in CI)
# - All findings structured for processing
```

## Customizing the Demo

### Add a Safe Migration

```bash
cat > db/migrate/20240200000100_safe_example.rb << 'EOF'
class SafeExample < ActiveRecord::Migration[6.0]
  def change
    add_table :safe_demo do |t|
      t.string :name
      t.timestamps
    end
    add_index :safe_demo, :name
  end
end
EOF

bundle exec queryguard analyze db/migrate
# Should show INFO finding for clean migration
```

### Add a Problematic Migration

```bash
cat > db/migrate/20240200000101_problematic.rb << 'EOF'
class Problematic < ActiveRecord::Migration[6.0]
  def change
    # This will be caught by QueryGuard
    add_column :users, :description, :text, null: false
  end
end
EOF

bundle exec queryguard analyze db/migrate
# Should show WARN finding
```

## Metrics for Demo Validation

During the demo, confirm:

| Metric | Expected | Status |
|--------|----------|--------|
| Total migrations analyzed | 6+ | ✓ |
| Critical findings | 1 | ✓ |
| Warning findings | 3+ | ✓ |
| Analysis time | <500ms | ✓ |
| JSON output | Valid JSON | ✓ |

---

*Demo Configuration Guide | QueryGuard*
