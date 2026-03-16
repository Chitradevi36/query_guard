# QueryGuard - Ruthless Product Audit

**TL;DR**: This is ~70% heuristic, 30% actual value. As shipped, it will generate **alert fatigue**, not prevent incidents. The migration analyzer has promise but needs context. Query analysis doesn't work without heavy setup.

---

## 1. Is This Useful For Rails Developers?

**Honest Answer**: Not yet. Not without significant changes.

### What Rails developers expect:
- Drop-in gem, works out of box → ✅ Yes, but...
- Catches real issues → ⚠️ 50%
- Few false positives → ❌ No
- Blocks deployments when it matters → ❌ No
- Doesn't break build on minor issues → ❌ No

### Why it fails:
1. **Default config is useless**: `analyze_query_risks=true` (enabled), but this generates noise without actual execution context
2. **No N+1 detection**: You need to manually set up subscriber + context tracking. Most devs won't do this
3. **No schema context**: Flags all `add_index` without `algorithm: :concurrently` - overkill for small tables
4. **This requires activation**: EXPLAIN analysis is `use_explain_plans=false` by default

**Red flag**: If I install this and get flooded with "SELECT * detected" warnings on admin queries or exports, I uninstall immediately.

---

## 2. What Feels Weak, Noisy, Uninstall-Worthy

### Tier 1: Definitely Uninstall (Next Week)

**A) SELECT * Detection** 
```ruby
# This is flagged as risky:
SELECT * FROM users WHERE id = ?  # ← Harmless query, but flagged

# Severity: WARN (default)
```
- ✅ Catches: Actual SELECT * in production code
- ❌ Problem: Also flags on tiny tables, admin contexts, temporary queries
- ❌ Problem: No context about downstream impact
- **Impact**: Alert fatigue. Developers ignore all warnings.

**B) LIKE Detection**
```ruby
# Flagged as risky:
WHERE user_name LIKE ?  # ← On indexed column, still flagged
```
- ✅ Catches: Unindexed LIKE (maybe)
- ❌ Problem: No schema awareness - can't tell if column is indexed
- ❌ Problem: Prefix matches are actually fine
- ❌ Problem: ILIKE is flagged the same severity as LIKE (ILIKE is slower)

**C) Migration Analysis Flags Everything**
```ruby
# All flagged as ERROR/WARN:
add_index :users, :email              # ← ERROR (no algorithm: :concurrently)
                                      # ← But table has 100 rows, why?

remove_column :users, :legacy_field   # ← Always ERROR
                                      # ← But you might have a safe approach

change_column :posts, :status, :text  # ← Always ERROR  
                                      # ← But maybe you coordinated downtime
```

- **Impact**: DevOps says "this blocks every PR". PR velocity drops.

### Tier 2: Frustrating (Uninstall Month 2)

**D) Join Count Detection**
```ruby
# Flagged as risky (risky_joins, 5+ tables):
SELECT *
FROM orders o
JOIN users u ON o.user_id = u.id
JOIN accounts a ON u.account_id = a.id
JOIN products p ON o.product_id = p.id
JOIN inventory i ON p.id = i.product_id
JOIN warehouses w ON i.warehouse_id = w.id
```
- ✅ Catches: Genuine complexity
- ❌ Problem: Legitimate reporting queries have 7+ joins
- ❌ Problem: No understanding of normalization
- **Impact**: Data team complains. "That report query is perfectly fine."

**E) Subquery Detection**
```ruby
# Flagged:
SELECT * FROM users WHERE id IN (SELECT user_id FROM posts)
```
- ✅ Sometimes slow (uncorrelated subqueries)
- ❌ But IN subqueries are often fine and more readable than JOIN
- ❌ No intelligence about query optimizer behavior
- **Impact**: Developers write worse queries to pass linting.

**F) Query Count Threshold**
```ruby
config.max_queries_per_request = 100  # ← Default
```
- ❌ This is WAY too high. Most endpoints shouldn't exceed 5-10
- ❌ But lowering it means legitimate endpoints fail
- ❌ No per-endpoint configuration
- **Impact**: Threshold is useless or constantly wrong.

---

## 3. Where Are False Positives Likely?

### High-Probability False Positive Scenarios

| Scenario | Current Behavior | Real Impact | Why False |
|----------|------------------|-------------|-----------|
| Admin/data export endpoint with SELECT * | ⚠️ WARN | Useless | Context: It's admin-only |
| Reports with 6-7 table joins | ⚠️ WARN/medium | Blocks PR | Legitimate analytical query |
| Prefix LIKE search `name LIKE 'A%'` | ⚠️ WARN | Blocks PR | Column IS indexed for prefix |
| Schema migrations on new, empty tables | 🔴 ERROR (add_index no :concurrently) | Blocks deployment | Table has 0 rows, goes fast |
| Safe column removal with backfill | 🔴 ERROR (remove_column) | Blocks deployment | Removal is the final step |
| Batch background job with 500 queries | ⚠️ WARN (query count) | Blocks PR | Background job, not request |
| Analytics query with 3 subqueries | ⚠️ WARN | Blocks PR | Correct analytic pattern |

**Core Problem**: Query risk detection is **schema-blind**. It can't tell:
- What columns are indexed
- What table sizes are
- Whether a query is in admin context
- Whether it's a request or background job

---

## 4. What Is Overengineered?

### Too Many Moving Parts

**A) Query Subscriber System**
```ruby
# Current architecture:
1. Subscriber listens to ActiveSupport::Notifications
2. Builds Context with all queries
3. Runs 6 different risk detectors
4. Generates findings
5. Optional: EXPLAIN enrichment
6. Optional: Upload to API
```

**Problems**:
- Requires setup in initializer
- Only works with ActiveRecord
- EXPLAIN requires live DB connection
- Most devs won't configure correctly
- Result: Query analysis doesn't work for ~80% of users

**Better**: Just analyze migrations. That's the real value.

---

**B) SourceMetadataCollector**
```ruby
# 330 lines for detecting:
# - Git SHA, branch, repository
# - 6 CI provider env vars
```

**Problems**:
- Adds complexity for feature nobody requested
- Works only on CI systems
- Only useful if you have SaaS backend to upload to
- Takes 330 lines that could've fixed false positives

**Reality Check**: This isn't "CI for database queries" - this is "send metadata to SaaS dashboard". Different problem.

---

**C) Explain Enrichment Layer**
```ruby
# PostgreSQLAdapter knows:
# - Seq Scan vs Index Scan
# - Row estimates
# - Execution time
# But default: disabled (use_explain_plans=false)
```

**Problems**:
- Complex feature that's slow (DB round-trip per query)
- Disabled by default, so nobody uses it
- Could give REAL insight ("missing index on users.email")
- But instead, ship defaults that are useless

**The Ask**: 
```ruby
# What developers WANT:
"Your query is slow because no index on users.email"

# What QueryGuard gives:
"SELECT * detected (WARN)"
"4 tables in JOIN (MEDIUM)"  
"Subquery detected (WARN)"
```

---

**D) Analyzer Registry + Disabled Analyzers**
```ruby
config.disable_analyzer(:slow_query)
config.enable_analyzer(:slow_query)
```

**Problems**:
- Why would I disable safety checks?
- Creates more configuration burden
- No production value

---

## 5. What's Missing For "CI For Database Queries"?

### The Actual Promise vs. Reality

**You Promise**: "CI/CD rigor for database operations"

**Reality Gap**:

| Promise | Current State | What Would Actually Deliver It |
|---------|---------------|----------------------------------|
| Stop risky migrations | Flags all migrations as risky | Only flag schema-aware risks (table size matters) |
| Catch N+1 queries | Heuristic detection only | Actual query execution tracing + analysis |
| Fail unsafe PRs | Generic thresholds | Context-aware rules (table size, columns, indexed?) |
| Query performance safety | SELECT * regex + join counting | EXPLAIN ANALYZE + index advisor |
| Database risk assessment | Regex pattern matching | Schema introspection + actual execution |
| Production incident prevention | Hope devs read warnings | Mandatory blocking on actual risks |

---

### Missing Critical Features

**A) Schema Introspection**
```
Currently: Flags remove_column as ERROR always
Should: Know if column being removed is:
  - Actually used? (search code)
  - Has dependent queries? (find them)
  - Can safely remove? (yes/no)
  
Also:
  - Is foreign key indexed? (yes → safe)
  - Is column indexed? (yes → locking risk for removal)
  - Table size? (100 rows → fast; 100M rows → slow)
```

**B) Query Execution Context**
```
Currently: Rules like "5+ JOINs = risky"
Should: Know:
  - Is this a request handler endpoint? (5+ joins = bad)
  - Is this a report/batch job? (20+ joins = fine)
  - What columns are actually selected? (SELECT * on 100 columns = bad)
  - Is it cached? (executes once per day = fine)
  - Row count expectation? (5 rows = ok; 5M rows = problem)
```

**C) Safe Patterns & Recommendations**
```
Currently: "remove_column locks table, use X gem"
Should: 
  - Link to specific safe migration patterns
  - Show exact code changes needed
  - Test the pattern in context
  - Approve automatically if pattern followed

Example:
  ✓ Column removal safe pattern detected
    - Backfill complete 
    - No code still references column
    - Safe to remove
```

**D) Build Failure Thresholds**  
```
Currently:
  config.max_queries_per_request = 100
  
Should:
  Per-endpoint rules:
    POST /api/users/search   → max 5 queries
    POST /api/analytics/export → max 500 queries
    POST /webhook/github     → max 10 queries
```

**E) Contextual Configuration**
```
Currently:
  block_select_star = false
  select_star_severity = :warn
  analyze_query_risks = true
  
Should:
  queriquard.configure do |config|
    config.allow_select_star :admin_only
    config.allow_select_star :exports, :reports
    config.fail_on :critical
    config.warn_on :high  
    config.ignore [:slow_query]  # Known false positive

    config.disable_in 'db/seeds.rb'
    config.disable_in 'spec/'
  end
```

---

## 6. What To Cut, Simplify, Or Rewrite

### LAUNCH CUTS (This Week)

**CUT: SourceMetadataCollector**
- **Why**: Not core to "CI for database queries"
- **Impact**: Saves 330 lines
- **User value**: 0 (nobody asked for this)
- **Risk**: Adds maintenance burden
- **Timeline**: Remove entirely, fold into CLI later if needed
- **Approval**: If you're launching as open source first, you don't need "send to SaaS backend"

**CUT: Analyzer Registry + Disabled Analyzers**
- **Why**: Configuration complexity nobody needs
- **Impact**: Saves 50 lines + mental load
- **What to keep**: Simple enable/disable, not registry pattern
- **Code change**: 
  ```ruby
  # Before:
  config.disable_analyzer(:slow_query)
  
  # After: (delete this, keep it simple)
  ```

**CUT: Select Star Analyzer (Default)**
- **Why**: High false positive rate
- **Change**: Make it opt-in, disabled by default
- **Config**: `config.detect_select_star = false  # default`
- **Approval**: Lose 10% of "safety" but gain 90% fewer false positives

**CUT: Complex Join Detector (5+ tables)**
- **Why**: Legitimate reporting queries have 6-7 joins
- **Change**: Increase threshold to 8+ tables
- **Better**: Remove entirely, let developers care about this
- **Reality**: Most N+1s are from `User.includes(:posts).map(&:view_count)`, not from JOIN count

**CUT: Subquery Detector**
- **Why**: Subqueries are often more readable than joins
- **Reality**: Real N+1 problems look different
- **Remove**: Delete entirely

---

### SIMPLIFY (Next 2 Weeks)

**Simplify: Configuration**
```ruby
# Before:
config.max_duration_ms_per_query = 100.0
config.slow_query_severity = :warn
config.query_count_severity = :warn
config.select_star_severity = :warn
config.analyze_query_risks = true
config.use_explain_plans = false

# After:
config.slow_query_threshold_ms = 100
config.max_queries_per_request = 20
```

Drop: 15 config options → 2 really matter
- Slow query threshold
- Max queries per request  

Everything else: Expert mode later.

---

**Simplify: Query Risk Analysis**
```ruby
# Current: 8 different risk detectors, mostly false positives

# New: 3 detectors that actually matter:
1. Slow query detection (requires EXPLAIN if enabled)
2. N+1 detection (requires query tracing, off by default)
3. Missing index detection (heuristic only, warn level)
```

---

**Simplify: Migration Analysis**
```ruby
# Current: Flag everything as ERROR/WARN

# New: Three levels:
🔴 DANGEROUS (needs special review):
   - remove_column
   - change_column type
   
🟡 CAUTION (might need downtime):
   - add_index without algorithm: :concurrently
   - add_not_null_constraint without default
   
🟢 OK:
   - create_table
   - add_column with default
   - drop_table (usually fine, already gone)
```

---

### REWRITE (Next Month)

**Rewrite: Query Risk Detection to use EXPLAIN**
```ruby
# Current: "5+ tables = risky"
# New: Actual execution analysis
#   - Get EXPLAIN ANALYZE
#   - Identify missing indexes
#   - Recommend new indexes
#   - Show estimated slowdown
```

This is the real value. Do it right.

---

**Rewrite: Migration Analyzer for Context**
```ruby
# New logic:

def analyze_migration(content)
  # 1. Parse migration operations
  # 2. For add_index: Check table size from DB
  #    - < 100K rows? No concurrent needed (WARN → INFO)
  #    - > 1M rows? CRITICAL, needs concurrent
  #    - > 10M rows? CRITICAL, needs more analysis
  
  # 3. For remove_column: Check if referenced
  #    - No code references? Safe (INFO)
  #    - Has code backfill? Safe (INFO)  
  #    - No backfill, still referenced? CRITICAL
  
  # 4. For change_column: Check downtime strategy
  #    - Migration includes manual downtime window? OK
  #    - Will run in maintenance window? OK
  #    - Otherwise WARN (requires nodowntime gem pattern)
end
```

---

## 7. Product Risk Assessment

### Why This Fails At Launch

**Scenario: Install QueryGuard, run on existing codebase**

```python
Day 1 - Installation
  ✓ Gem installs fine
  ✓ Run: bundle exec queryguard analyze db/migrate
  ✓ Get output: 8 CRITICAL, 12 WARN, 15 INFO

Day 2 - Team Review
  "Wait, ALL these migrations are unsafe?"
  "We've run all of these in production fine"
  "What's wrong with SELECT *?"
  "Our reports have 6 JOINs and they work great"

Week 1 - Attempted Integration  
  Add to CI to fail on CRITICAL
  Result: CI broken. Roll back.

Week 2 - Feedback
  "This tool flags everything"
  "Too noisy"
  "False positives everywhere"
  → Gem uninstalled
```

**Root Cause**: Doesn't understand context.

---

### How To Turn This Around

**Single most important change**: **Make migration analysis schema-aware.**

```ruby
# CURRENT (wrong):
add_index :users, :email  # Flag as ERROR

# PROPOSED (right):
# 1. Query database: How many rows in users?
# 2. If < 100K: INFO "Can lock briefly, no concurrent needed"
# 3. If > 1M: CRITICAL "Needs algorithm: :concurrently or downtime"
# 4. Show actual risk: "Locking for ~2 seconds on 50K row table"
```

This single change turns:
- Alert fatigue → useful warnings
- Uninstalls → adoption

---

## 8. Go/No-Go For Launch

### Current Status: 🔴 DO NOT SHIP

**Critical Issues**:
- [ ] Migration false positives (flags everything as risky)
- [ ] Query detection is 90% heuristic, 10% value
- [ ] No schema context whatsoever
- [ ] Configuration is too complex
- [ ] SourceMetadataCollector adds no value
- [ ] SELECT * detector (false positive machine)
- [ ] Join/Subquery detectors (noisy)
- [ ] README oversells what actually works

### Launch Criteria (Choose One)

**Option A: Ship ONLY Migration Analysis (Tight Scope)**
```
Focus: Just analyze migrations for actual risks
Remove: Query analysis, analyzers, explain enrichment
Result: Simple, useful, launch-ready
Timeline: 1 week
Features to keep:
  ✅ Migration risk detection (with false positive fixes)
  ❌ Query analysis (enable later)
  ❌ SourceMetadataCollector
  ❌ Explain enrichment
```

**Option B: Fix False Positives First (Medium Scope)**
```
Focus: Keep everything, but make it less noisy
Work: Add context to all detectors
Timeline: 3 weeks
  ✅ Schema-aware migration analysis
  ✅ Query analysis opt-in instead of default
  ✅ Reduce thresholds (JOIN from 5→8, etc)
  ✅ Per-endpoint rules for query count
```

**Option C: Fix Everything (Long Timeline)**
```
Timeline: 8 weeks, probably not worth it
- Rewrite query analysis to use EXPLAIN
- Add schema introspection
- Build safe migration patterns library
- Context-aware configuration
- Approval workflows
```

---

## Recommended Path Forward

### This Week (LAUNCH)
1. **Remove** SourceMetadataCollector (cuts 330 lines of waste)
2. **Remove** SelectStarAnalyzer (opt-in, not default)
3. **Remove** ComplexJoinDetector, SubqueryDetector (too noisy)
4. **Fix** MigrationAnalyzer to check table size:
   - `add_index` on small table → INFO not ERROR
   - `remove_column` without references → INFO not ERROR
   - `change_column` → WARN with recommendation
5. **Simplify** config to 3 options max
6. **Update** README: Be honest about what works (migrations) vs. what's experimental (queries)
7. **Fix demo** to show real output with context

### Next 2 Weeks
1. Add schema introspection to migration analyzer
2. Make query analysis opt-in
3. Fix integration tests

### Ship When
- Migration analyzer has <10% false positive rate
- Query analysis requires explicit opt-in
- Config fits on 1 page

---

## Summary

**What QueryGuard Got Right**:
- ✅ Migration risk detection concept is solid
- ✅ CLI UX is clean
- ✅ JSON output is well structured
- ✅ Demo migrations show real patterns

**What QueryGuard Got Wrong**:
- ❌ Query analysis is premature without execution context
- ❌ SourceMetadataCollector adds no value for open source launch
- ❌ Too many false positives (SELECT *, JOINs, subqueries)
- ❌ Configuration overengineering
- ❌ README oversells what actually works
- ❌ Explains product as "CI for database queries" but is "regex pattern matcher + optional EXPLAIN"

**Call**: Cut scope, fix false positives, launch tight MVP.

The promise is good. The execution needs ruthless simplification before it's real.

---

*Written by: Senior Engineer / Founder audit*
*Date: March 16, 2026*
