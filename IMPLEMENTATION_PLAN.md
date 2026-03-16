# QueryGuard - Concrete Fixes (Implementation Plan)

This is the step-by-step work to fix the critical issues identified in the audit.

---

## Phase 1: Cuts (16 Hours)

### 1.1 Remove SourceMetadataCollector Entirely (3 hours)

**Why**: Adds 330 lines, 0 product value for open source launch.

**Files to Delete**:
- `lib/query_guard/cli/source_metadata_collector.rb` (330 lines)
- `spec/cli/source_metadata_collector_spec.rb` (400+ lines)

**Files to Update**:
- `lib/query_guard.rb` - Remove require
- `lib/query_guard/cli/json_reporter.rb` - Remove SourceMetadataCollector usage
- Tests that reference it

**Exit Criteria**:
- All tests pass (will lose 35 metadata tests, gain what we want)  
- No references to source_metadata_collector remain
- CLI still works, JSON output is cleaner

---

### 1.2 Remove SelectStarAnalyzer as Default (2 hours)

**Why**: High false positive rate, causes frustration immediately.

**Keep But Disable**:
```ruby
# lib/query_guard/analyzers/select_star_analyzer.rb
# ← Keep the code, but change behavior

# lib/query_guard/config.rb
# Change from:
@block_select_star = false
@select_star_severity = :warn

# To:
@block_select_star = false  # Default OFF
@select_star_severity = :warn
```

**New Docs**:
```markdown
# Enable SELECT * detection in your app config if desired:
QueryGuard.configure do |config|
  config.block_select_star = true
end
```

**Tests**:
- Update tests to verify it's disabled by default
- Keep detector tests but mark as "opt-in feature"

---

### 1.3 Remove ComplexJoinDetector & SubqueryDetector (2 hours)

**Delete These Classes**:
- `lib/query_guard/analysis/risk_detectors.rb` - Remove ComplexJoinRiskDetector (lines 123-153)
- `lib/query_guard/analysis/risk_detectors.rb` - Remove SubqueryRiskDetector (lines 155-188)

**Remove From QueryRiskClassifier**:
```ruby
# In lib/query_guard/analysis/query_risk_classifier.rb
# Remove from @detectors:
# ComplexJoinRiskDetector.new,
# SubqueryRiskDetector.new,
```

**Tests**:
- Delete test cases for these detectors
- Update QueryRiskClassifier tests

**Exit Criteria**:
- No references to removed detectors
- Core tests still pass
- False positive count drops by 40%

---

### 1.4 Remove Disabled Analyzers Registry (1 hour)

**Simplify config.rb**:
```ruby
# REMOVE this:
attr_accessor :disabled_analyzers

# REMOVE method:
def disable_analyzer(name)
def enable_analyzer(name)
```

**Why**: Configuration complexity nobody needs.

---

### 1.5 Remove SourceMetadata From JSON Reporter (2 hours)

**Files**:
- `lib/query_guard/cli/json_reporter.rb` - Remove source_metadata_collector injection
- Remove `build_source` enhancement for metadata
- Keep basic source (path) information only

**JSON Output Before**:
```json
{
  "source": {
    "path": "/app/db/migrate",
    "metadata": {
      "git": { "sha": "..." },
      "ci": { "provider": "..." }
    }
  }
}
```

**JSON Output After**:
```json
{
  "source": {
    "path": "/app/db/migrate"
  }
}
```

**Exit Criteria**:
- JSON simpler, no metadata field
- All JSON tests pass (will need updates)
- File size smaller

---

### 1.6 Simplify Config (6 hours) 

**Current Config**:
- 15+ attributes
- Confusing option names
- Too many severity levels

**New Config** (3 fundamental options):
```ruby
# lib/query_guard/config.rb
attr_accessor :enabled_environments,
              :max_queries_per_request,      # Most important
              :max_duration_ms_per_query,    # Most important
              :raise_on_violation,
              :log_prefix,
              :migrations_directory,
              :uploader_type,                # Keep for future, unused now
              :api_base_url,
              :project_key,
              :api_token

# DELETE: 
# block_select_star
# analyze_query_risks (option analysis)
# use_explain_plans
# select_star_severity
# query_count_severity
# slow_query_severity
# ignored_sql (move to CLI tool, not gem)
# disabled_analyzers
```

**New Defaults**:
```ruby
@enabled_environments = %i[development test]
@max_queries_per_request = 20  # Lower, more realistic default
@max_duration_ms_per_query = 100.0
@raise_on_violation = false
@migrations_directory = "db/migrate"
# Uploader stuff for future

# DELETE all other analyzers config
# They always run if registered
```

**Exit Criteria**:
- Config is readable on 1 page
- All tests updated to use new API
- No broken deprecations

---

## Phase 2: False Positive Fixes (24 Hours)

### 2.1 Make Migration Analyzer Schema-Aware (16 hours)

**Current Problem**:
```ruby
add_index :users, :email  # Flagged as ERROR always
# But table might have 0 rows, 100 rows, or 1 billion rows
# Risk varies 100x
```

**Solution**: Check table size, adjust severity:

```ruby
# lib/query_guard/migrations/migration_analyzer.rb

def analyze_migration(file_path)
  content = File.read(file_path)
  migration_name = File.basename(file_path, ".rb")

  risks = MigrationRiskDetectors.detect_risks(content, migration_name)
  
  # NEW: Enhance risks with table size awareness
  risks = enhance_risks_with_table_context(risks, content)

  risks_to_findings(risks, file_path)
end

private

def enhance_risks_with_table_context(risks, content)
  # Try to get database connection (optional)
  # If available, check table sizes
  
  # Parse migration for table name references
  # If table exists, get row count from DB
  # Adjust severity based on table size
  
  risks.map do |risk|
    if risk[:type] == :index_not_concurrent
      # Check table size
      table_name = extract_table_from_context(content, risk[:line_number])
      if table_name && table_exists?(table_name)
        row_count = get_row_count(table_name)
        
        # Adjust severity:
        if row_count < 100_000        # < 100K rows
          risk[:severity] = :info
          risk[:message] += " (Small table, locking <1s)"
        elsif row_count < 1_000_000   # < 1M rows
          risk[:severity] = :warn
          risk[:message] += " (Medium table, locking ~1-5s)"
        else                           # > 1M rows
          risk[:severity] = :error
          risk[:message] += " (Large table, locking >5s, use algorithm: :concurrently)"
        end
      end
    elsif risk[:type] == :remove_column
      # Check if column is still referenced in code
      column_name = extract_column_from_context(content, risk[:line_number])
      
      references = search_codebase_for_column(column_name)
      if references.empty?
        risk[:severity] = :info
        risk[:message] = "Safe to remove (no code references found)"
      elsif backfill_detected_in_migration?(content)
        risk[:severity] = :info
        risk[:message] = "Backfill completed in same migration, safe to remove"
      else
        risk[:severity] = :warn
        risk[:message] = "Remove detected. Ensure: (1) backfill complete, (2) no code references"
      end
    elsif risk[:type] == :change_column
      # change_column is risky but depends on context
      risk[:severity] = :warn
      risk[:message] = "Type change locks table. If downtime accepted, OK. Otherwise use: add_column + backfill + drop + rename pattern"
    end
    
    risk
  end
end

# Helper to try getting DB connection
def get_table_row_count(table_name)
  begin
    # Try ActiveRecord if available
    if defined?(ActiveRecord::Base)
      ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM #{table_name}").first['count'] || 0
    end
  rescue
    nil  # Fail gracefully if no DB connection
  end
end

def search_codebase_for_column(column_name)
  # Search app/ and lib/ for references to this column
  # Return matching files
  # (Simplified; would use actual code search in production)
end

def backfill_detected_in_migration?(content)
  # Look for execute() or raw SQL updates in same migration
  content.include?("execute") || content.include?("UPDATE")
end
```

**Testing**:
```ruby
# spec/migrations/migration_analyzer_spec.rb

describe "schema-aware detection" do
  it "marks add_index as INFO for small tables" do
    # Setup: Small table in DB
    migration = %{
      class AddIndex < ActiveRecord::Migration[6.0]
        def change
          add_index :users, :email
        end
      end
    }
    
    findings = analyzer.analyze(migration)
    expect(findings.first[:severity]).to eq :info
    expect(findings.first[:message]).to include("Small table")
  end
  
  it "marks remove_column as WARN if column is referenced" do
    # Setup: Column exists in code
    migration = %{
      class RemoveColumn < ActiveRecord::Migration[6.0]
        def change
          remove_column :users, :legacy_field
        end
      end
    }
    
    findings = analyzer.analyze(migration)
    expect(findings.first[:severity]).to eq :warn
    expect(findings.first[:message]).to include("code references")
  end
end
```

---

### 2.2 Reduce Query Risk False Positives (8 hours)

**Fix: MissingIndexRiskDetector is too aggressive**

```ruby
# lib/query_guard/analysis/risk_detectors.rb

class MissingIndexRiskDetector < RiskDetector
  # CHANGE: Only flag ILIKE (slow), not LIKE
  def detect(query, config)
    risks = []
    sql = query.sql

    # Only flag ILIKE (accent-insensitive, always slow)
    if sql.match?(/\bILIKE\b/i)
      risks << {
        pattern: :ilike_without_index,
        risk_level: :medium,  # Changed from high
        message: "ILIKE (case-insensitive, accent-insensitive search) is slow on unindexed columns",
        metadata: {
          recommendation: "Use indexed full-text search or denormalized columns for case-insensitive search",
          impact: "Sequential scan; consider refactoring approach"
        }
      }
    end
    
    # REMOVE: LIKE detection (too many false positives)
    # REMOVE: Function in JOIN detection (false positives on legitimate patterns)

    risks
  end
end
```

**Exit Criteria**:
- Fewer warnings per typical query log
- No warning on standard LIKE queries
- Tests pass

---

### 2.3 Update Configuration Defaults (4 hours)

```ruby
# lib/query_guard/config.rb

def initialize
  @enabled_environments = %i[development test]
  @max_queries_per_request = 20          # DOWN from 100
  @max_duration_ms_per_query = 100.0
  @raise_on_violation = false
  @log_prefix = "[QueryGuard]"
  @migrations_directory = "db/migrate"
  
  # Register analyzers
  @analyzer_registry = Analyzers::Registry.new
  @analyzer_registry.register(:slow_query, Analyzers::SlowQueryAnalyzer.new)
  @analyzer_registry.register(:query_count, Analyzers::QueryCountAnalyzer.new)
  # REMOVE: SelectStarAnalyzer (opt-in only)
  @analyzer_registry.register(:query_risk, Analyzers::QueryRiskAnalyzer.new)
  @analyzer_registry.register(:migration_risk, Migrations::MigrationAnalyzer.new)
end
```

---

## Phase 3: README & Documentation (8 Hours)

### 3.1 Rewrite README to Be Honest

**Current**: "CI for database queries"
**New**: "Migration safety analyzer + optional query analysis"

```markdown
# QueryGuard: Migration Safety

**Automatically catch dangerous migration patterns before they ship.**

QueryGuard analyzes your Rails migrations to detect:
- ❌ Unsafe index additions (locking on large tables)
- ❌ Risky column operations (data loss, long locks)
- ❌ NOT NULL additions without defaults
- ❌ Raw SQL that might fail on rollback

Works out of the box. No setup required.

## What It Catches

### Dangerous Patterns (CRITICAL)
- `remove_column` - data loss risk
- `change_column` - table rewrite, extended lock

### Caution Patterns (WARN) 
- `add_index` without `algorithm: :concurrently` on large tables
- `add_column ... not null` without default value

### Clean Migrations (INFO)
- `create_table`
- `add_column ... default: X`
- `drop_table`
- `add_index ... algorithm: :concurrently`

## Installation

```ruby
gem 'query_guard'
bundle install
```

## Usage

```bash
# Analyze your migrations:
bundle exec queryguard analyze db/migrate

# Output:
✓ Analyzed 28 migrations
🔴 CRITICAL: 1 (remove_column on posts)
🟡 WARN: 3 (index additions on large tables)
🟢 INFO: 24 (safe migrations)

# Fail your build on critical issues:
bundle exec queryguard check db/migrate --threshold critical
# Exit: 1 if CRITICAL findings
```

## How It Works

1. **Scans migrations** for risky patterns (regex + AST)
2. **Checks database** for table sizes (adjusts severity)
3. **Searches code** for column references (determines safety)
4. **Reports findings** with recommendations

## Key Design

- **Fast**: No EXPLAIN queries by default
- **Accurate**: Schema-aware severity
- **Minimal**: One feature, done well

## False Positives?

QueryGuard is designed to have <5% false positive rate by being conservative.

- Small tables (< 100K rows): `add_index` = INFO
- Unambiguous safety (no code refs): `remove_column` = INFO
- Legitimate data operations: Automatically marked safe

## Optional: Query Analysis

You can also analyze query patterns (experimental):

```ruby
QueryGuard.configure do |config|
  config.max_duration_ms_per_query = 100
  config.max_queries_per_request = 20
end

# This detects:
# - Slow queries (>100ms)
# - Too many queries per request (>20)
```

**Note**: Query analysis requires query tracing setup. See docs for details.

## Configuration

```ruby
QueryGuard.configure do |config|
  # Analyzer thresholds
  config.max_queries_per_request = 20    # Max queries/request (experimental)
  config.max_duration_ms_per_query = 100 # Max ms per query (experimental)
  
  # Build control
  config.raise_on_violation = false      # Raise exception vs. warn
  config.enabled_environments = %i[development test]
  
  # Paths
  config.migrations_directory = "db/migrate"
end
```

## CI Integration

GitHub Actions:

```yaml
name: Database Safety

on:
  pull_request:
    paths:
      - 'db/migrate/**'
  push:
    branches: [main]

jobs:
  query-guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.2
          bundler-cache: true
      
      - name: Check migrations
        run: bundle exec queryguard check db/migrate --threshold critical
```

## Roadmap

- v0.5: Schema-aware migration analysis ← You are here
- v0.6: Query analysis with live execution tracing
- v1.0: SaaS dashboard integration (optional)
```

**Exit Criteria**:
- README is honest about what works
- Promises match reality
- Gets <10% "false positives" complaint rate from users

---

### 3.2 Update Demo to Show Real Findings

**Update**: `demo/README.md` to reflect new output:
- Fewer findings overall
- Clearer explanations
- Schema context shown

---

## Phase 4: Testing (8 Hours)

### 4.1 Update All Tests
- Remove SourceMetadataCollector tests (gone)
- Remove SelectStarAnalyzer from defaults
- Remove ComplexJoin, Subquery tests
- Add schema-aware migration tests
- Update JSON reporter tests (no metadata field)

### 4.2 Integration Tests
```ruby
# spec/integration/false_positives_spec.rb

describe "false positive rate" do
  it "doesn't warn on small table indexes" do
    # Setup table with 50 rows
    # Migration: add_index :small_table, :column
    # Result: INFO, not ERROR
  end
  
  it "doesn't warn on unreferenced column removal" do
    # Column: legacy_field (not referenced in code)
    # Migration: remove_column :users, :legacy_field
    # Result: INFO, not ERROR
  end
  
  it "doesn't warn on legitimate multi-table joins" do
    # Query with 7 tables (legitimate reporting query)
    # Result: No warning
  end
end
```

---

## Timeline Summary

| Phase | Work | Hours | Days |
|-------|------|-------|------|
| 1 | Cuts (remove noise) | 16 | 2 |
| 2 | False positive fixes | 24 | 3 |
| 3 | Documentation | 8 | 1 |
| 4 | Testing | 8 | 1 |
| **Total** | **Complete relaunch** | **56** | **~1 week** |

---

## Success Metrics

### Before (Current)
```
8 migrations analyzed
→ 1 CRITICAL (real)
→ 6 WARN (4 are false positives)
→ 1 INFO

False positive rate: 66%
Likely outcome: "This tool flags everything" → Uninstall
```

### After (Target)
```
8 migrations analyzed
→ 1 CRITICAL (remove_column, real)
→ 1 WARN (add_index on 50M row table, real)
→ 6 INFO (safe migrations)

False positive rate: <5%
Likely outcome: "This is useful" → Keep installed
```

---

## Go/No-Go Check

**Ready to launch when**:
- [ ] All cuts completed (3 fewer analyzers, simpler config)
- [ ] Migration analyzer is schema-aware (table size considered)
- [ ] False positive rate is <5% on real codebase
- [ ] README is honest and doesn't oversell
- [ ] All tests pass (fewer tests OK, higher quality)
- [ ] Demo output shows realistic findings

**Not ready if**:
- [ ] Still flagging small table add_index as ERROR
- [ ] Still flagging safe column removal as ERROR
- [ ] Config is still 15+ options
- [ ] Query analysis promises are overstated

---

This plan is executable and gets to "actually useful" in 1 week of focused work.
