# QueryGuard JSON API Reference

## Overview

QueryGuard supports JSON output for programmatic access to analysis results. This enables integration with CI dashboards, security tools, and automated workflows.

## Command-Line Usage

```bash
# Output migration analysis as JSON
bundle exec queryguard analyze --format json

# Save to file for CI processing
bundle exec queryguard analyze --format json > analysis.json

# With custom output path
bundle exec queryguard analyze --format json --output results.json
```

## Response Schema

### Top-Level Response

```json
{
  "status": "success|partial|error",
  "findings": [...],
  "metadata": {...},
  "timestamp": "2024-01-15T10:30:00Z",
  "version": "0.4.0"
}
```

### Status Values

- **success**: All migrations analyzed successfully; no errors
- **partial**: Some migrations analyzed; some skipped or errors encountered
- **error**: Analysis failed; check error_message for details

### Error Response

```json
{
  "status": "error",
  "error_message": "Database connection failed",
  "timestamp": "2024-01-15T10:30:00Z",
  "version": "0.4.0"
}
```

## Findings

Each finding represents a detected risk or issue in your migrations.

```json
{
  "findings": [
    {
      "id": "finding_uuid",
      "type": "risky_migration|missing_rollback|performance_issue|schema_conflict",
      "severity": "critical|high|medium|low",
      "message": "Human-readable description of the issue",
      "file": "db/migrate/20240101120000_add_users_table.rb",
      "line": 15,
      "column": 6,
      "context": {
        "migration_name": "AddUsersTable",
        "operation": "create_table",
        "details": {...}
      },
      "recommendation": "Optional suggestion to fix the issue"
    }
  ]
}
```

### Finding Types

#### Risky Migration
Detects operations that may cause issues in production.

```json
{
  "type": "risky_migration",
  "severity": "high",
  "message": "Adding non-nullable column without default value",
  "context": {
    "operation": "add_column :users, :status, :string, null: false",
    "problem": "This will fail if users table has existing rows",
    "solution": "Add default: 'active' or backfill in a data migration"
  }
}
```

#### Missing Rollback
Detects migrations that can't be safely rolled back.

```json
{
  "type": "missing_rollback",
  "severity": "critical",
  "message": "Migration lacks rollback logic for destructive operation",
  "context": {
    "operation": "remove_column :users, :api_key",
    "problem": "No 'add_column' in down method; data loss on rollback"
  }
}
```

#### Performance Issue
Detects operations that may cause locking or high I/O.

```json
{
  "type": "performance_issue",
  "severity": "medium",
  "message": "Adding index without concurrent: true on large table",
  "context": {
    "table": "events",
    "table_size_rows": 5000000,
    "operation": "add_index :events, :user_id",
    "solution": "Use add_index :events, :user_id, algorithm: :concurrently"
  }
}
```

#### Schema Conflict
Detects migrations that contradict current schema.

```json
{
  "type": "schema_conflict",
  "severity": "high",
  "message": "Migration creates column that already exists in current schema",
  "context": {
    "column": "created_at",
    "table": "users",
    "conflicting_migration": "20231201120000_add_timestamps.rb"
  }
}
```

### Severity Levels

| Level | Priority | Recommendation |
|-------|----------|----|
| critical | Block deployment | Must fix before PR merge |
| high | Review before deploy | Fix in this deployment or skip with justification |
| medium | Monitor | Plan fix for next deployment |
| low | Informational | Nice to fix, not blocking |

## Metadata

Provides context about the analysis execution.

```json
{
  "metadata": {
    "environment": "test",
    "database": "postgresql",
    "database_version": "14.5",
    "schema_version": "20240115105000",
    "migrations_analyzed": 42,
    "migrations_skipped": 0,
    "analysis_duration_ms": 1250,
    "ci_context": {
      "provider": "github_actions",
      "branch": "main",
      "commit": "abc123def456",
      "pull_request_number": 123
    }
  }
}
```

## Complete Example

```json
{
  "status": "partial",
  "findings": [
    {
      "id": "qg_20240115_001",
      "type": "risky_migration",
      "severity": "high",
      "message": "Adding non-nullable column to existing table without default",
      "file": "db/migrate/20240115100000_add_user_status.rb",
      "line": 4,
      "context": {
        "migration_name": "AddUserStatus",
        "operation": "add_column",
        "table": "users",
        "column": "status",
        "column_type": "string",
        "null_value": false,
        "has_default": false
      },
      "recommendation": "Add a default value: add_column :users, :status, :string, null: false, default: 'active'"
    },
    {
      "id": "qg_20240115_002",
      "type": "missing_rollback",
      "severity": "critical",
      "message": "No rollback logic for drop_table operation",
      "file": "db/migrate/20240114090000_remove_legacy_data.rb",
      "line": 8,
      "context": {
        "migration_name": "RemoveLegacyData",
        "operation": "drop_table",
        "table": "legacy_users"
      },
      "recommendation": "Add table definition to down method: def down; create_table :legacy_users do |t| ... end; end"
    }
  ],
  "metadata": {
    "environment": "test",
    "database": "postgresql",
    "database_version": "14.5",
    "schema_version": "20240114090000",
    "migrations_analyzed": 23,
    "migrations_skipped": 0,
    "analysis_duration_ms": 1840,
    "ci_context": {
      "provider": "github_actions",
      "branch": "add-user-status",
      "commit": "abc123def456789",
      "pull_request_number": 456
    }
  },
  "timestamp": "2024-01-15T10:35:22.123Z",
  "version": "0.4.0"
}
```

## CI Integration Examples

### GitHub Actions: Post Results to Summary

```yaml
- name: Analyze migrations
  id: analysis
  run: bundle exec queryguard analyze --format json > analysis.json

- name: Report results
  if: always()
  run: |
    echo "## Database Migration Analysis" >> $GITHUB_STEP_SUMMARY
    cat analysis.json | jq '.findings[] | "- [\(.severity)] \(.message) (\(.file))"' >> $GITHUB_STEP_SUMMARY
```

### CI: Store Results as Artifact

```yaml
- name: Analyze migrations
  run: bundle exec queryguard analyze --format json > migrations.json

- name: Upload results
  uses: actions/upload-artifact@v3
  with:
    name: migration-analysis
    path: migrations.json
```

### Custom: Parse and Check Severity

```bash
#!/bin/bash
# fail-on-critical.sh

CRITICAL_COUNT=$(jq '[.findings[] | select(.severity == "critical")] | length' analysis.json)

if [ "$CRITICAL_COUNT" -gt 0 ]; then
  echo "❌ Found $CRITICAL_COUNT critical issues"
  exit 1
else
  echo "✅ No critical migration issues"
  exit 0
fi
```

## Version History

| Version | Status | Changes |
|---------|--------|---------|
| 0.4.0 | Current | JSON API stable |
| 0.3.0 | Previous | Initial JSON support |

## Error Handling

QueryGuard returns different exit codes for different scenarios:

| Exit Code | Meaning |
|-----------|---------|
| 0 | Analysis successful; no critical issues |
| 1 | Analysis failed (error response) |
| 2 | Analysis succeeded but critical issues found |

## Rate Limiting & Performance

- Analysis runs per-request in CI
- Typical analysis time: 500-3000ms depending on migration count
- No API rate limits for JSON output

## Backward Compatibility

- JSON schema will be versioned separately from QueryGuard releases
- New fields added with default values to maintain compatibility
- Deprecated fields marked 2 releases before removal

## Support

For issues with JSON output:

1. Check QueryGuard version: `bundle exec queryguard --version`
2. Verify database connection: `bundle exec rails db:version`
3. Enable debug logging: `QUERY_GUARD_DEBUG=1 bundle exec queryguard analyze --format json`
4. Report at: [GitHub Issues](https://github.com/yourusername/query_guard/issues)
