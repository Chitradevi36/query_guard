# QueryGuard - Concrete Fixes for Launch Blockers

This document has the **exact code changes** needed to fix each blocker. No ambiguity, copy-paste ready.

---

## CRITICAL FIX #1: Add Rails Dependency to Gemspec

**File**: `query_guard.gemspec`  
**Time**: 2 minutes  
**Impact**: CRITICAL

**Current**:
```ruby
spec.add_dependency "activesupport", ">= 5.2", "< 8.0"
```

**Change to**:
```ruby
spec.add_dependency "activesupport", ">= 5.2", "< 8.0"
spec.add_dependency "rails", ">= 5.2", "< 8.0"
```

**Why**: Makes Rails requirement explicit, prevents install-time errors

**Verify**:
```bash
cd query_guard
gem build query_guard.gemspec
gem install ./query_guard-*.gem
bundle exec queryguard --version
# Should work without errors
```

---

## CRITICAL FIX #2: Add --version Sanity Check (Defer Rails Loading)

**File**: `exe/queryguard`  
**Time**: 10 minutes  
**Impact**: CRITICAL

**Current**:
```ruby
#!/usr/bin/env ruby
require "bundler/setup"
require "query_guard"
require "query_guard/cli"

begin
  QueryGuard::CLI.run(ARGV)
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.join("\n") if ENV['DEBUG']
  exit 1
end
```

**Change to**:
```ruby
#!/usr/bin/env ruby

# Handle --version early (before loading Rails)
if ARGV.first == '--version' || ARGV.first == '-v'
  # Load only what's needed for version
  $LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
  require 'query_guard/version'
  puts "QueryGuard v#{QueryGuard::VERSION}"
  exit 0
end

# Now load everything else
require "bundler/setup"
require "query_guard"
require "query_guard/cli"

begin
  QueryGuard::CLI.run(ARGV)
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.join("\n") if ENV['DEBUG']
  exit 1
end
```

**Why**: Users can run `queryguard --version` without needing Rails/DB

**Verify**:
```bash
bundle exec queryguard --version
# Should output: QueryGuard v0.4.0
# Should NOT require Rails to be installed
```

**Bonus**: Update help text in CLI to mention version command:
```ruby
# In lib/query_guard/cli.rb print_help method:
puts <<~HELP
  QueryGuard CLI

  USAGE:
    queryguard COMMAND [OPTIONS]

  COMMANDS:
    analyze     Analyze migrations and queries
    check       Check if risks exceed threshold
    --version   Show version
    --help      Show this help
```

---

## CRITICAL FIX #3: Rewrite README Value Proposition

**File**: `README.md` (lines 1-50)  
**Time**: 1-2 hours  
**Impact**: CRITICAL

**Current**:
```markdown
# QueryGuard: CI for Database Queries

**Stop risky database changes before they reach production.**

QueryGuard automatically analyzes your migrations and queries during CI to catch:
- ❌ Unsafe query patterns (N+1 queries, SELECT *)
- ❌ Destructive migrations (dropping columns without backfill)
...
```

**Change to**:
```markdown
# QueryGuard: Migration Safety for Rails

**Prevent dangerous database migrations from reaching production.**

QueryGuard analyzes your Rails migrations to catch:
- 🔴 Unsafe operations (column removal, type changes)
- 🔴 Data loss risks (dropping columns without backfill)
- 🔴 Performance problems (missing index concurrency flags)
- 🔴 NOT NULL additions without defaults

**What it detects**: Migration-level risks that can break production  
**What it doesn't**: Detect application-level query problems (future feature)

## Installation

```ruby
gem 'query_guard'
bundle install
bundle exec queryguard analyze db/migrate
```

## What You Get

QueryGuard runs in two places:

### 1. During Development
```bash
bundle exec queryguard analyze db/migrate
```

Local analysis with optional database context for more accurate severity.

### 2. In CI/CD
```yaml
jobs:
  database_safety:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
      - name: Check migrations
        run: bundle exec queryguard check db/migrate --threshold error
```

Blocks deployment if findings exceed threshold.

## Example Output

```
Analyzing: db/migrate

🔴 CRITICAL (1 finding)
  remove_column :users, :phone_number
  Removing a column locks the table for 10-30 seconds
  → Use safe_remove_column gem or schedule downtime

🟡 WARN (2 findings)
  add_index :posts, :user_id
  Index on 50M row table without algorithm: :concurrently
  → Add algorithm: :concurrently to avoid locks

✅ INFO (15 findings)
  No issues with other migrations
```

## Configuration (Optional)

```ruby
# config/initializers/query_guard.rb
QueryGuard.configure do |config|
  config.enabled_environments = %i[development test]
  # Migrations are always analyzed; no additional config needed
end
```

Default is safe; no configuration required.

## When Does It Need Your Database?

QueryGuard can work with or without a database:

**With database** (more accurate):
```bash
DATABASE_URL=postgres://... queryguard analyze db/migrate
```

- Checks table sizes (what's "safe" depends on size)
- Detects column references in other migrations
- More accurate severity levels

**Without database** (estimates):
```bash
queryguard analyze db/migrate
```

- Uses defaults for table sizes
- Estimates conservative severity
- Works in CI without DB setup

#### Example: Same Migration, Different Contexts

```ruby
add_index :users, :email

# With DB (10K rows):
# → INFO: "Index on small table, no concurrency needed"

# Without DB:
# → WARN: "Index without algorithm: :concurrently (estimated)"
```

Output notes which situation applies:

```
Analyzing: db/migrate

ℹ️  Database context: Connected to PostgreSQL
   [more accurate results with actual table sizes]
```

```
Analyzing: db/migrate

⚠️  Database context: Not available
   [using conservative severity estimates]
   Run with DATABASE_URL=... for improved accuracy
```

## How To Use in CI

### GitHub Actions (Recommended)

```yaml
name: Database Safety Check

on:
  pull_request:
    paths:
      - 'db/migrate/**'
  push:
    branches: [main]

jobs:
  query_guard:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
          bundler-cache: true

      - name: Set up database
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/test
        run: bundle exec rake db:create db:migrate

      - name: Check migrations
        run: bundle exec queryguard check db/migrate --threshold critical
```

**Exit codes**:
- `0` = Safe to deploy
- `1` = Findings above threshold, block deployment
- `2` = Error running check

## Frequently Asked Questions

**Q: Why does it need Rails?**  
A: QueryGuard uses ActiveRecord to parse migrations and access schema information. For non-Rails projects, use different tool.

**Q: What about query analysis (N+1, SELECT *, etc)?**  
A: Query analysis is experimental and disabled by default. Enable in config if interested, but findings may have false positives.

**Q: Why do results differ between local and CI?**  
A: If your CI environment doesn't have database access, severity estimates use conservative defaults. Run with DATABASE_URL= for consistent results.

**Q: Can I silence specific findings?**  
A: Not yet, we're building this for v0.5. Open an issue if you need this.

## Roadmap

- **v0.4.0** (current): Migration analysis with schema awareness
- **v0.5**: Exclusion rules, per-migration configs
- **v0.6**: Query analysis with real execution tracing
- **v1.0**: SaaS dashboard integration

---
```

This is the rewritten README. Exact changes:
1. Title: "CI for Database Queries" → "Migration Safety for Rails"
2. Lead: Honest about what it catches vs. doesn't
3. Add "With/Without Database" context section (key user blocker)
4. Simplify config section (just defaults, no 8 options)
5. Add FAQ (real user questions)
6. Add Roadmap (managing expectations)

**Verify**:
- [ ] Test that README accurately describes what code actually does
- [ ] Check example output matches real output
- [ ] Verify CI example works

---

## CRITICAL FIX #4: Add Database Context Warning to Output

**File**: `lib/query_guard/cli/commands/analyze.rb`  
**Time**: 10 minutes  
**Impact**: CRITICAL

**Current**:
```ruby
def execute
  unless path_exists?
    puts "Error: Path does not exist: #{path_absolute}"
    exit 1
  end

  unless @options[:json] || @options[:format] == 'json'
    puts "Analyzing: #{path_absolute}"
    puts "(This may take a moment...)\n"
  end

  migration_files = find_migration_files(@path)
  # ... continues
```

**Change to**:
```ruby
def execute
  unless path_exists?
    puts "Error: Path does not exist: #{path_absolute}"
    exit 1
  end

  unless @options[:json] || @options[:format] == 'json'
    puts "Analyzing: #{path_absolute}"
    
    # NEW: Show database context
    adapter = get_database_adapter
    if adapter
      puts "Database context: Connected (accurate severity)\n"
    else
      puts "Database context: Not available (conservative estimates)"
      puts "  For more accurate results, run: DATABASE_URL=... queryguard analyze\n"
    end
    
    puts "(This may take a moment...)\n"
  end

  migration_files = find_migration_files(@path)
  # ... continues
```

**Verify**:
```bash
# Without DB:
$ queryguard analyze db/migrate
Analyzing: db/migrate
Database context: Not available (conservative estimates)
  For more accurate results, run: DATABASE_URL=... queryguard analyze

# With DB:
$ DATABASE_URL=postgres://... queryguard analyze db/migrate
Analyzing: db/migrate
Database context: Connected (accurate severity)
```

---

## CRITICAL FIX #5: Simplify Configuration

**File**: `config/initializers/query_guard.rb` (example)  
**Time**: 30 minutes  
**Impact**: CRITICAL

**Current**:
```ruby
QueryGuard.configure do |c|
  c.enabled_environments      = %i[development test]
  c.max_queries_per_request   = 100
  c.max_duration_ms_per_query = 100.0
  c.block_select_star         = false
  c.ignored_sql               = [/^PRAGMA /i, /^SAVEPOINT/i]
  c.raise_on_violation        = false
  c.log_prefix                = "[QueryGuard]"
end
```

**Change to** (in config/initializers/query_guard.rb example):
```ruby
# Typical setup - migration analysis enabled by default
QueryGuard.configure do |config|
  # Migrations are always analyzed
  config.enabled_environments = %i[development test]
  
  # Optional: query analysis (see docs for what to expect)
  # config.max_queries_per_request = 20
  # config.max_duration_ms_per_query = 100
end
```

And update `lib/query_guard/config.rb` defaults:
```ruby
def initialize
  # Keep only essential options:
  @enabled_environments = %i[development test]
  @max_queries_per_request = nil      # Disabled by default
  @max_duration_ms_per_query = nil    # Disabled by default
  @migrations_directory = "db/migrate"
  
  # DELETE or hide:
  # @block_select_star
  # @ignored_sql
  # @raise_on_violation
  # @log_prefix
  # @select_star_severity
  # ... etc
end
```

**Why**:  
- Most users don't need to touch config
- Defaults work for 95% of cases
- Less paralysis

**Verify**:
```bash
# With default config, no error:
bundle exec queryguard analyze db/migrate
```

---

## CRITICAL FIX #6: Document JSON Output in README

**File**: `README.md` (add new section)  
**Time**: 30 minutes  
**Impact**: CRITICAL

**Add this section**:

```markdown
## Machine-Readable Output (JSON)

For integrations with dashboards, alerts, and CI systems:

```bash
queryguard analyze db/migrate --json > report.json
```

### Output Format

```json
{
  "command": "analyze",
  "path": "db/migrate",
  "database_context": "connected",
  "findings": [
    {
      "severity": "critical",
      "analyzer": "migration_risk",
      "rule": "remove_column",
      "title": "Unsafe column removal",
      "file": "db/migrate/20240301_remove_phone.rb",
      "line": 3,
      "description": "Removing a column rewrites the entire table, causing lock",
      "recommendation": "Use gem 'safe-migrations' or schedule downtime",
      "metadata": {
        "operation": "remove_column",
        "column": "phone_number",
        "table": "users"
      }
    }
  ],
  "summary": {
    "total": 3,
    "critical": 1,
    "error": 0,
    "warn": 2,
    "info": 0
  },
  "version": "0.4.0"
}
```

### Sending to Slack

```bash
#!/bin/bash
queryguard check db/migrate --json | python3 - <<'EOF'
import json, sys, urllib.request

report = json.load(sys.stdin)
if report['summary']['critical'] > 0:
  msg = f"❌ {report['summary']['critical']} critical migration risks"
  urllib.request.urlopen(urllib.request.Request(
    "https://hooks.slack.com/...",
    data=json.dumps({"text": msg}).encode()
  ))
EOF
```

### Storing Artifacts (GitHub Actions)

```yaml
- name: Analyze migrations
  run: queryguard analyze --json > qg-report.json

- name: Upload report
  uses: actions/upload-artifact@v3
  with:
    name: queryguard-report
    path: qg-report.json
    retention-days: 30
```
```

**Verify**:
```bash
queryguard analyze db/migrate --json | python3 -m json.tool
# Should output valid JSON with no errors
```

---

## TIMELINE SUMMARY

| Fix | Time | Effort |
|-----|------|--------|
| #1: Add Rails dependency | 2 min | Trivial |
| #2: --version sanity check | 10 min | Trivial |
| #3: Rewrite README | 2 hrs | Moderate |
| #4: Database context warning | 10 min | Trivial |
| #5: Simplify config | 30 min | Trivial |
| #6: Document JSON | 30 min | Trivial |
| **Total** | **3.5 hrs** | **Moderate** |

---

## Testing Checklist

After all fixes, verify:

```bash
# Installation
gem install query_guard
queryguard --version
# ✅ Should work without Rails

# CLI 
bundle exec queryguard analyze db/migrate
# ✅ Should show database context

bundle exec queryguard check db/migrate --threshold critical
# ✅ Should exit with code 0/1 properly

# JSON output
bundle exec queryguard analyze --json | python3 -m json.tool
# ✅ Should output valid JSON

# Gem dependency
cat query_guard.gemspec | grep "add_dependency.*rails"
# ✅ Should show rails requirement

# Help text
bundle exec queryguard --help
# ✅ Should mention --version and --json
```

---

## Order of Implementation

1. **Do #1, #2, #4 first** (fixes blocking issues)
2. **Then #3 (README)** (most visible)
3. **Then #5, #6** (quality improvements)
4. **Test everything** before merging

---

## Success Criteria

When all 6 fixes are done:

✅ **Installation doesn't break** 
- `gem install query_guard` works
- `queryguard --version` works without Rails error

✅ **Value prop is honest**
- README says what it catches
- README says what it doesn't catch yet
- Users know what to expect

✅ **No silent failures**
- Database context is explicit in output
- Users know why results differ locally vs. CI

✅ **Configuration is simple**
- Most users need 0 config
- Defaults are sensible

✅ **Hidden features are documented**
- JSON output works and is documented
- Users can integrate with dashboards

✅ **Ready for launch**
- Tag v0.4.0
- Announce on Ruby community channels
- Confident it will work for users

Done. You're ready to ship.
