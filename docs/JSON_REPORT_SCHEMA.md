# QueryGuard JSON Report Schema

**Version**: 1.0  
**Purpose**: Stable, versioned JSON output for SaaS ingestion, CI integration, and external tooling.  
**Last Updated**: March 16, 2026

---

## Overview

This document defines the JSON report schema for QueryGuard analysis and check commands. This is a **public contract** for:

- SaaS platforms ingesting QueryGuard results
- CI/CD systems integrating with QueryGuard
- External tools and dashboards parsing QueryGuard output
- Compliance and audit systems archiving findings

All tools consuming QueryGuard JSON output should:
1. **Validate `report_version`** to ensure compatibility
2. **Handle missing optional fields** gracefully
3. **Treat the schema as immutable** within a major version
4. **Request schema extensions** via issues, not expect undocumented fields

---

## Complete Schema

### Root Report Object

```json
{
  "report_version": "1.0",
  "report_type": "analysis|check",
  "timestamp": "2026-03-16T14:30:00Z",
  "tool": {
    "name": "queryguard",
    "version": "0.5.0"
  },
  "source": {
    "path": "/app/db/migrate",
    "command": "analyze|check",
    "threshold": "error"
  },
  "summary": {
    "total_findings": 5,
    "by_severity": {
      "critical": 1,
      "error": 2,
      "warn": 2,
      "info": 0
    },
    "files_analyzed": 10,
    "files_with_findings": 3
  },
  "findings": [
    {
      "id": "abc123def456",
      "analyzer": "query_risk_analyzer",
      "rule": "remove_column",
      "severity": "error",
      "title": "Removing column detected",
      "description": "Removing columns from tables can result in data loss.",
      "file_path": "db/migrate/20260316000001_remove_email_from_users.rb",
      "line_number": 5,
      "recommendation": [
        "Use a reversible migration with add_column in rollback",
        "Consider archiving the data elsewhere before removal",
        "Coordinate with team before deploying to production"
      ],
      "metadata": {
        "table_name": "users",
        "operation": "remove_column",
        "estimated_table_rows": 150000
      }
    }
  ],
  "metadata": {
    "total_files_checked": 10,
    "has_index_suggestions": true,
    "has_migration_steps": true,
    "execution_time_ms": 1234
  }
}
```

---

## Field Reference

### Top Level

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `report_version` | string | ✅ Yes | Schema version (e.g., "1.0"). Used for compatibility checks. |
| `report_type` | enum | ✅ Yes | Either "analysis" (detailed) or "check" (pass/fail gate). |
| `timestamp` | string (ISO8601) | ✅ Yes | When the report was generated. Format: "2026-03-16T14:30:00Z" |
| `tool` | object | ✅ Yes | Information about the tool that generated the report. |
| `source` | object | ✅ Yes | Information about what was analyzed. |
| `summary` | object | ✅ Yes | High-level statistics about findings. |
| `findings` | array | ✅ Yes | Array of Finding objects (may be empty). |
| `metadata` | object | ❌ No | Additional context (execution time, file counts, etc). |

### `tool` Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | ✅ Yes | Always "queryguard" |
| `version` | string | ✅ Yes | Version of QueryGuard that generated this report (e.g., "0.5.0") |

### `source` Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | ✅ Yes | The path that was analyzed (e.g., "/app/db/migrate") |
| `command` | string | ✅ Yes | The command used: "analyze" or "check" |
| `threshold` | string | ❌ No | The threshold used for check command: "critical", "error", "warn", or "info" |

### `summary` Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `total_findings` | number | ✅ Yes | Total number of findings (sum of all severities) |
| `by_severity` | object | ✅ Yes | Count of findings by severity (see below) |
| `files_analyzed` | number | ✅ Yes | Total number of files checked |
| `files_with_findings` | number | ✅ Yes | Count of files that have at least one finding |

### `summary.by_severity` Object

| Field | Type | Value | Description |
|-------|------|-------|-------------|
| `critical` | number | 0+ | Count of critical findings |
| `error` | number | 0+ | Count of error findings |
| `warn` | number | 0+ | Count of warnings |
| `info` | number | 0+ | Count of info findings |

**Note**: All severity fields are always present (may be 0), even if no findings at that level.

### Finding Object (in `findings` array)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | ✅ Yes | Unique ID for this finding (first 16 chars of SHA256 hash). Used for deduplication. |
| `analyzer` | string | ✅ Yes | Name of the analyzer that detected this (e.g., "query_risk_analyzer") |
| `rule` | string | ✅ Yes | Name of the rule that triggered (e.g., "remove_column") |
| `severity` | enum | ✅ Yes | One of: "critical", "error", "warn", "info" |
| `title` | string | ✅ Yes | Human-readable title of the finding |
| `description` | string | ✅ Yes | Detailed description of what was found and why it matters |
| `file_path` | string | ❌ No | Path to the file containing the issue |
| `line_number` | number | ❌ No | Line number where the issue was found |
| `recommendation` | array | ❌ No | Array of strings suggesting how to fix the issue |
| `metadata` | object | ❌ No | Additional context-specific data (structure varies by analyzer) |

### `metadata` Object (at root level)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `total_files_checked` | number | ❌ No | Total files that were analyzed |
| `has_index_suggestions` | boolean | ❌ No | Whether any findings include index suggestions |
| `has_migration_steps` | boolean | ❌ No | Whether any findings include migration steps |
| `execution_time_ms` | number | ❌ No | How long the analysis took in milliseconds |

### Finding `metadata` Object

Structure varies by analyzer and rule. Common fields:

| Field | Type | Description |
|-------|------|-------------|
| `table_name` | string | Name of the database table this finding relates to |
| `operation` | string | Database operation being performed (e.g., "remove_column", "change_column") |
| `estimated_table_rows` | number | Row count in the table (if database connection available) |
| `index_sql` | string | SQL for a suggested index |
| `suggested_indexes` | array | Multiple suggested indexes |
| `migration_steps` | array | Step-by-step guidance for safe migration |
| `safe_rollout_strategy` | string | Strategy for safely deploying this change |

---

## Severity Levels

| Severity | Usage | Exit Code (Check) | Blocks Deployment |
|----------|-------|-------------------|-------------------|
| `critical` | Rare, severe issues (unused indexes, N+1 queries) | 1 | Yes (if --threshold critical) |
| `error` | Risky operations (remove_column, change_column) | 1 | Yes (default threshold: error) |
| `warn` | Caution-level issues (column renames, SELECT *) | 0/1 | Yes (if --threshold warn) |
| `info` | Informational (low-risk patterns) | 0 | No (only with --threshold info) |

---

## Design Decisions

### Why versioning?

The schema is designed to evolve. By including `report_version`, consumers can:
- Validate compatibility before processing
- Handle future versions gracefully
- Request breaking changes via major version bumps

### Why is `report_version` always "1.0"?

This document describes version 1.0. Changes to:
- Field names = BREAKING (major version bump: 2.0)
- Required fields = BREAKING (major version bump: 2.0)
- New optional fields = NON-BREAKING (minor bump: 1.1)
- New severity values = NON-BREAKING (minor bump: 1.1)
- New finding types = NON-BREAKING (minor bump: 1.1)

### Why allow missing optional fields?

Real-world use cases have gaps:
- No file path available for certain analyzers
- Database connection not available (estimated_table_rows = nil)
- Some recommendations may not apply (recommendation = [])

Consumers should handle gracefully.

### Why `found` object vs. flat array?

The nested structure allows:
- Easy filtering by severity or analyzer
- Clear separation of summary from details
- Room for future top-level fields without breaking consumers

---

## Usage Examples

### Example 1: Analyze Command Output

```bash
$ queryguard analyze db/migrate --format json | jq .
```

Output: Detailed report with all findings listed.

### Example 2: Check Command with Threshold

```bash
$ queryguard check db/migrate --threshold error --format json
```

Output: Same schema, but exit code (0/1/2) indicates pass/fail.

### Example 3: SaaS Ingestion

```python
import json
import requests

# Parse QueryGuard output
report = json.loads(queryguard_output)

# Validate schema version
if report['report_version'] != '1.0':
    raise ValueError(f"Unsupported schema version: {report['report_version']}")

# Process findings
for finding in report['findings']:
    if finding['severity'] == 'critical':
        alert_team(finding)
    
    # Store in database
    Finding.create({
        'external_id': finding['id'],
        'analyzer': finding['analyzer'],
        'rule': finding['rule'],
        'severity': finding['severity'],
        'title': finding['title'],
        'metadata': finding.get('metadata', {})
    })
```

### Example 4: CI Integration

```bash
#!/bin/bash

# Run check and capture JSON output
output=$(bundle exec queryguard check db/migrate --format json --threshold error)

# Extract summary for logging
echo "Migrations checked:"
echo "$output" | jq '.summary'

# Check exit code
if [ $? -eq 1 ]; then
    echo "Risky migrations detected!"
    echo "$output" | jq '.findings[] | select(.severity == "error")'
    exit 1
fi
```

---

## Future Considerations

### Version 1.1 (planned non-breaking additions)

- New severity level: `advisory` 
- New top-level field: `extended_summary` with risk score
- New finding metadata: `references` (links to documentation)
- New source field: `git_commit` or `branch`

### Version 2.0 (future breaking changes)

- Rename `analyzer` to `analyzer_name` (consistency)
- Rename `rule` to `rule_name`
- Split `metadata` into analyzer-specific sub-objects
- Flatten finding structure (remove nesting)

---

## Compliance & Stability

This schema is:

✅ **Documented**: Every field explained and typed.  
✅ **Versioned**: Explicit version field for compatibility.  
✅ **Validated**: Tests ensure all output conforms.  
✅ **Stable**: No changes within 1.x line without notice.  
✅ **Extensible**: Optional fields and metadata allow evolution.  
✅ **Public**: This is the contract between QueryGuard and consumers.

---

## Testing This Schema

### Validate JSON Output

```bash
# Run with JSON output
queryguard analyze db/migrate --format json > report.json

# Validate structure with jq
jq '.report_version, .summary.total_findings, .findings | length' report.json

# Check all required fields exist
jq 'if .report_version and .findings then "valid" else "invalid" end' report.json
```

### Test with a JSON Schema Validator

```bash
# Using ajv-cli or similar
ajv validate -s queryguard-report-schema.json -d report.json
```

---

## Support & Questions

If you need:
- **New fields**: Open an issue describing use case (will add in 1.1)
- **Different structure**: Open discussion (may be breaking, would be 2.0)
- **Examples**: See section above or check test files
- **Validation**: Use provided JSON schema file or write tests

This schema is a **commitment to stability** for external integrations.

---

**Current Version**: 1.0  
**Stable Since**: March 16, 2026  
**Next Review**: When first extension needed
