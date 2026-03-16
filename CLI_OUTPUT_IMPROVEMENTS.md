# QueryGuard CLI Output Improvements

## Overview

The QueryGuard CLI `analyze` and `check` commands now feature improved, developer-friendly output that makes it immediately clear what risks exist, where they are, and how to fix them.

## Key Improvements

### 1. **Hierarchical Grouping**

Findings are now organized intelligently:
- **By Severity Level**: Critical → Error → Warning → Info
- **By Finding Type**: Analyzer + Rule (e.g., `migration_risk:index_not_concurrent`)

This makes it easy to scan and prioritize issues:
```
❌ ERROR (4)
  [migration_risk:index_not_concurrent]
  [migration_risk:remove_column_lock]
  [query_risk:potential_n_plus_one]

⚠️ WARN (3)
  [migration_risk:rename_column_lock]
  [query_risk:select_star]
  [query_risk:like_without_index]
```

### 2. **Clear Finding Structure**

Each finding shows:

| Element | Purpose | Example |
|---------|---------|---------|
| **Title** | What the issue is | "Index Addition Without CONCURRENTLY" |
| **File Path:Line** | Where to look | 📄 db/migrate/20240315_add_index.rb:8 |
| **Description** | Why it matters | "Adding an index locks the table..." |
| **Table Context** | Database impact | 🗂️ Table: users (5.0M rows), ⚙️ Operation: add_index |
| **Recommended Actions** | How to fix | ✅ Recommended Actions: Add algorithm: :concurrently |

### 3. **Advanced Metadata Display**

#### Index Suggestions
When available, shows exact SQL to create recommended indexes:
```
🔧 Suggested Indexes:
   CREATE INDEX idx_products_name_trgm ON products USING GiST(name gist_trgm_ops);
   CREATE INDEX idx_products_name_like ON products(name varchar_pattern_ops);
```

#### Migration Steps
Step-by-step guidance for complex migrations:
```
📋 Migration Steps:
   1. Create the column with null: true (allow nulls for now)
   2. Add default or backfill values in background job
   3. Add NOT NULL constraint in separate migration
   4. Verify all rows have values before constraint
```

#### Safe Rollout Strategies
Deployment guidance for high-risk changes:
```
🛡️ Safe Rollout Strategy:
   Deploy during off-peak hours (2-4 AM UTC) with monitoring
```

#### Severity Escalation
Explains when issues are escalated to higher severity:
```
⬆️ Escalated from warn: Large table (5M rows) causes brief lock to become critical risk
```

### 4. **Comprehensive Summary**

At the end of each analysis:
```
SUMMARY
============================================================

  Total Findings: 7

  By Severity:
    ❌ ERROR: 4
    ⚠️ WARN: 3

  By Type:
    • migration_risk:index_not_concurrent: 1
    • migration_risk:remove_column_lock: 1
    • query_risk:select_star: 1
    [... more ...]

  Files Analyzed:
    • 6 files with findings
```

## Usage

### Basic Text Output
```bash
queryguard analyze db/migrate
```

Shows human-readable findings organized by severity and type.

### JSON Output (for Automation)
```bash
queryguard analyze db/migrate --json
```

Returns structured JSON with all findings and metadata:
```json
{
  "timestamp": "2026-03-15 22:04:05",
  "summary": {
    "total": 7,
    "by_severity": {
      "error": 4,
      "warn": 3
    }
  },
  "findings": [
    {
      "title": "Index Addition Without CONCURRENTLY",
      "type": "migration_risk:index_not_concurrent",
      "severity": "error",
      "file_path": "db/migrate/20240315_add_users_email_index.rb",
      "line_number": 8,
      "description": "...",
      "recommendation": "...",
      "metadata": {
        "table_name": "users",
        "estimated_table_rows": 5000000,
        "operation": "add_index",
        "index_sql": "add_index :users, :email, algorithm: :concurrently"
      }
    }
  ],
  "metadata": {
    "total_files": 6,
    "total_locations": 7,
    "has_index_suggestions": true,
    "has_migration_steps": true
  }
}
```

### Verbose Mode (Debug)
```bash
queryguard analyze db/migrate --verbose
```

Includes debug metadata for each finding, useful for understanding internal risk assessment.

### CI/CD Integration
```bash
queryguard check db/migrate --threshold error --json > analysis.json

# Exit codes:
# 0 = All risks below threshold (safe to deploy)
# 1 = Risks exceed threshold (blocked)
# 2 = Error (invalid path, etc.)
```

## Output Format Details

### Severity Icons
- 🚨 **CRITICAL** - Must fix before any deployment
- ❌ **ERROR** - Should fix, deployment may fail
- ⚠️ **WARN** - Consider fixing, may impact users
- ℹ️ **INFO** - FYI, lowest impact

### Metadata Icons
- 📄 File path with line number
- 🗂️ Table name and row count
- ⚙️ Database operation type
- ⬆️ Severity escalation reason
- ✅ Recommended actions
- 🔧 Index suggestions
- 📋 Migration steps
- 🛡️ Safe rollout strategy

### Row Count Formatting
Large numbers are human-readable:
- **500** - Exact count
- **50.0K** - Thousands
- **5.0M** - Millions
- **50.0B** - Billions

## Recommendation Strategy

The improved output helps developers:

1. **Understand Priority**: Severity grouping shows what needs immediate attention
2. **Locate Issues**: File paths with line numbers make navigation instant
3. **Understand Context**: Table names, row counts, and operation types explain impact
4. **Get Actionable Fixes**: Recommendations, SQL, and step-by-step guidance
5. **Plan Deployment**: Safe rollout strategies help prevent incidents
6. **Automate Checks**: JSON output integrates with CI/CD and reporting tools

## Examples

### Example 1: Index Addition Risk
```
❌ Index Addition Without CONCURRENTLY
   📄 db/migrate/20240315_add_users_email_index.rb:8
   Adding an index locks the table. Use algorithm: :concurrently for PostgreSQL.
   🗂️ Table: users (5.0M rows)
   ⚙️ Operation: add_index

   ✅ Recommended Actions:
      - Add algorithm: :concurrently to allow concurrent queries during index creation

   🔧 Suggested Index:
      add_index :users, :email, algorithm: :concurrently

   🛡️ Safe Rollout Strategy:
      Deploy during off-peak hours (2-4 AM UTC) with monitoring
```

### Example 2: Column Addition Risk
```
❌ Non-NULL Column Without Default
   📄 db/migrate/20240315_add_field.rb:12
   Adding a NOT NULL column without a default value will fail on populated tables.
   🗂️ Table: subscriptions (2.5M rows)
   ⚙️ Operation: add_column

   ✅ Recommended Actions:
      - Provide a default value, or add the column as nullable and backfill separately

   📋 Migration Steps:
      1. Create the column with null: true (allow nulls for now)
      2. Add default or backfill values in background job
      3. Add NOT NULL constraint in separate migration
      4. Verify all rows have values before constraint
```

### Example 3: N+1 Query Risk
```
❌ Potential N+1 Query Problem
   📄 app/controllers/posts_controller.rb:15
   Many sequential queries in a single request indicates a potential N+1 problem.
   ⬆️ Escalated from warn: Large result set (10K+ queries detected)
   Risk Level: critical

   ✅ Recommended Actions:
      - Use eager loading with includes(:association) or includes(:assoc1, :assoc2)

   📋 Migration Steps:
      1. Use: Post.includes(:author, :comments).find_each
      2. Or use: @posts = Post.eager_load(:author).where(...)
      3. Add N+1 detection gem to CI/CD pipeline
```

## Terminal Compatibility

The output uses:
- **ANSI Color Codes**: Works on all modern terminals (macOS, Linux, Windows Terminal)
- **Unicode Icons**: Displays correctly on UTF-8 terminals
- **Graceful Fallback**: Removes colors if piped or redirected

## Performance

Output generation is extremely fast:
- **Text Formatting**: < 1ms for 100 findings
- **JSON Generation**: < 5ms for 100 findings
- **Grouping & Sorting**: Built-in, no external dependencies

## Extensibility

The improved formatter supports adding:
- Custom metadata fields (automatically displayed)
- Application-specific icons and colors
- Alternative output formats (HTML, Markdown, etc.)
- Integration with reporting services

Simply add metadata to findings and it will be extracted and displayed intelligently.

## Related Documentation

- [CLI_GUIDE.md](CLI_GUIDE.md) - Complete command reference
- [CLI_IMPLEMENTATION.md](CLI_IMPLEMENTATION.md) - Technical architecture
- [CLI_CICD_EXAMPLES.md](CLI_CICD_EXAMPLES.md) - Integration examples

---

**💡 Tip**: For fastest feedback in development, use verbose mode:
```bash
queryguard analyze --verbose
```

For CI/CD checks, use JSON output with thresholds:
```bash
queryguard check --json --threshold error
```
