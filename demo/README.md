# QueryGuard Demo

A minimal Rails demo app showcasing QueryGuard's detection capabilities.

## What's Included

This demo contains intentional anti-patterns to demonstrate QueryGuard's ability to catch:

### Migrations with Issues

| Migration | Issue Detected | Severity |
|-----------|---|----------|
| `20240101_create_users` | Baseline (clean) | ✅ INFO |
| `20240102_add_posts_table` | Foreign key without index | ⚠️ WARN |
| `20240103_add_index_on_posts_content` | Index on large table without CONCURRENTLY | ⚠️ WARN |
| `20240104_remove_phone_from_users` | **Removing column causes data loss** | 🔴 CRITICAL |
| `20240105_add_comments_table` | Baseline (clean) | ✅ INFO |
| `20240106_add_status_to_users` | NOT NULL without default value | ⚠️ WARN |

### Query Anti-Patterns (in models)

| Pattern | Issue | Impact |
|---------|-------|--------|
| `User.select('*')` | SELECT * loads all columns | Performance |
| `user.posts.count` in loop | N+1 queries | Scalability |
| `post.comments.last` | Inefficient query | Performance |
| Unindexed foreign keys | Missing indexes | Slow queries |

---

## Quick Start

### 1. Build Demo (Linux/Mac)

```bash
cd query_guard/demo

# Set up demo database configuration
export DATABASE_URL="postgres://postgres:postgres@localhost:5432/queryguard_demo"

# Install dependencies
bundle install

# Create database
bundle exec rake db:create db:migrate
```

### 2. Run QueryGuard Analysis

```bash
# Analyze migrations for safety issues
bundle exec queryguard analyze db/migrate

# Check with error threshold (should find critical issues)
bundle exec queryguard check db/migrate --threshold error

# Get JSON output for programmatic use
bundle exec queryguard analyze db/migrate --format json > analysis.json
```

### 3. Expected Output

#### Quick Analysis

```bash
$ bundle exec queryguard analyze db/migrate
✓ analyzed 6 migrations
✓ analyzed 125 queries
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔴 CRITICAL: 1 finding
🟡 WARN:     3 findings
🟢 INFO:     2 findings

CRITICAL Findings:
  [20240104] remove_phone_from_users: Removing column (data loss risk)

WARN Findings:
  [20240103] add_index_on_posts_content: Index on large table (locking risk)
  [20240106] add_status_to_users: NOT NULL without default (migration failure risk)
  [20240102] add_posts_table: Foreign key without index (performance risk)
```

#### Detailed Analysis

```bash
$ bundle exec queryguard analyze db/migrate --verbose
```

Expected to show detailed findings for each migration with recommendations.

#### JSON Output

```bash
$ bundle exec queryguard analyze db/migrate --format json
```

Returns structured JSON with:
- Each finding with severity level
- Line number in migration file
- Specific recommendations
- Metadata (table names, estimated rows, etc.)

---

## Use Cases

### 1. Testing QueryGuard Locally

```bash
cd demo
bundle exec queryguard analyze db/migrate
# Observe findings
```

### 2. Recording Demo Videos

```bash
# Run with verbose output
bundle exec queryguard analyze db/migrate --verbose

# Or with JSON for showing structure
bundle exec queryguard analyze db/migrate --format json | jq
```

### 3. Validating New Features

Add new migrations to `db/migrate/` and test QueryGuard detection:

```bash
# Add a new problematic migration
vim db/migrate/20240107000007_new_issue.rb

# Test detection
bundle exec queryguard analyze db/migrate
```

### 4. CI/CD Integration Testing

```bash
# Test with check command (for CI integration)
bundle exec queryguard check db/migrate --threshold critical
echo $?  # Should return 1 (has critical findings)

bundle exec queryguard check db/migrate --threshold warn
echo $?  # Should return 1 (has warning findings)

bundle exec queryguard check db/migrate --threshold info
echo $?  # Should return 0 (all info level or below)
```

---

## Structure

```
demo/
├── db/
│   └── migrate/           # Sample migrations with issues
│       ├── 01_create_users.rb
│       ├── 02_add_posts_table.rb
│       ├── 03_add_index_on_posts_content.rb
│       ├── 04_remove_phone_from_users.rb (CRITICAL)
│       ├── 05_add_comments_table.rb
│       └── 06_add_status_to_users.rb
├── app/
│   └── models/            # Example models with query anti-patterns
│       ├── user.rb
│       └── post.rb
├── Gemfile
└── README.md (this file)
```

---

## Key Findings Reference

### CRITICAL: Data Loss

**Migration**: `20240104_remove_phone_from_users.rb`
**Issue**: Removing column without backfill
**Why it matters**: Immediate, irreversible data loss
**Fix**: Archive data first, then remove in follow-up migration

### WARNING: Locking Risk

**Migration**: `20240103_add_index_on_posts_content.rb`
**Issue**: Creating index without CONCURRENTLY
**Why it matters**: Table will be locked during index creation
**Fix**: Use `algorithm: :concurrently` on PostgreSQL

### WARNING: Migration Failure Risk

**Migration**: `20240106_add_status_to_users.rb`
**Issue**: NOT NULL column without default
**Why it matters**: Migration fails if table has existing rows
**Fix**: Add default value

### WARNING: Performance Risk

**Migration**: `20240102_add_posts_table.rb`
**Issue**: Missing index on foreign key usage
**Why it matters**: Foreign key queries become slow on large tables
**Fix**: Add appropriate indexes

---

## Extending the Demo

### Add Your Own Problematic Migration

```bash
# Create a new migration
touch db/migrate/20240107000007_your_migration.rb

# Add problematic code:
cat > db/migrate/20240107000007_your_migration.rb << 'EOF'
class YourMigration < ActiveRecord::Migration[6.0]
  def change
    # Your anti-pattern here
  end
end
EOF

# Test it
bundle exec queryguard analyze db/migrate
```

### Add Query Examples

Modify `app/models/` to include more query anti-patterns for demonstration:

```ruby
# In app/models/comment.rb
class Comment < ApplicationRecord
  belongs_to :post

  # ⚠️  ANTI-PATTERN: Unbounded SELECT *
  def full_display
    select('*').find(id)
  end
end
```

---

## Performance Expectations

### Database Setup

- **Time to initialize**: ~30 seconds
- **Space**: ~5-10 MB for demo database
- **Queries in demo**: 125 total (intentionally varied)

### QueryGuard Execution

- **Analysis time**: 200-500ms (depends on schema size and complexity)
- **Check time**: 150-300ms (faster - just threshold comparison)
- **JSON generation**: adds ~50ms

---

## Troubleshooting

### "Database not found"

```bash
export DATABASE_URL="postgres://user:password@localhost:5432/queryguard_demo"
bundle exec rake db:create
```

### "gem 'query_guard' source is local"

The Gemfile references QueryGuard from the parent directory (`path: ".."`)

```bash
# Make sure you're running from the demo directory
cd query_guard/demo
bundle install
```

### "Migration file not found"

```bash
# Demo migrations are in db/migrate/
ls db/migrate/
# Should show 20240101_*.rb through 20240106_*.rb
```

---

## For Marketing & Documentation

This demo is perfect for:

### Creating Screenshots
```bash
bundle exec queryguard analyze db/migrate --verbose
# Terminal output shows real detection
```

### Creating Videos
```bash
# Start fresh
bundle exec rake db:drop db:create db:migrate

# Show analysis
bundle exec queryguard analyze db/migrate

# Highlight findings
# Show JSON output
bundle exec queryguard analyze db/migrate --format json | jq '.findings'
```

### Writing Blog Posts
Use the migrations as real examples of:
- What not to do in migrations
- How to fix each issue
- Why each issue matters

### Conference Talks
Demonstrate live analysis of real-world patterns and QueryGuard's detection capabilities.

---

## Success Criteria

When you run this demo, you should see:

✅ **1 CRITICAL finding** - removing column without backfill  
✅ **3 WARNING findings** - locking risk, NOT NULL, missing index  
✅ **2 INFO findings** - clean migrations  

This validates that QueryGuard correctly identifies:
- Data loss risks
- Performance risks
- Migration best practice violations

---

## Next Steps

1. **Run the demo locally**
   ```bash
   cd demo
   bundle install
   bundle exec queryguard analyze db/migrate
   ```

2. **Review the findings** - Understand what QueryGuard detects

3. **Experiment** - Add more migrations to test different patterns

4. **Use for marketing** - Screenshots, videos, blog posts

5. **Collect feedback** - Are the detections accurate? Any false positives?

---

*Created March 16, 2026 | QueryGuard Demo for Product Validation*
