# QueryGuard SaaS Platform API Specification

**Document Version**: 1.0  
**Last Updated**: March 16, 2026  
**Scope**: JSON API contract for hosted QueryGuard platform and integrations

---

## Overview

QueryGuard provides stable, versioned JSON output for SaaS platform ingestion. This document defines:

1. **Report Schema Versioning** - How the schema will evolve
2. **API Versioning Strategy** - Request/response version negotiation
3. **Backward Compatibility** - What we guarantee
4. **Deprecation Policy** - How we sunset old versions
5. **Extension Points** - Where platforms can customize

---

## 1. Report Schema Versioning

### Version Format

Reports use **MAJOR.MINOR** versioning:

```
report_version: "1.0"  # MAJOR.MINOR
               └─┬─┘   
                 └─ Increment for any breaking change
```

### Version Guarantees

**Within a major version (1.x, 2.x, etc.)**:

- ✅ **New optional fields** can be added (non-breaking)
- ✅ **New nested objects** can be introduced if properly handled
- ✅ **Recommendations array** can accept more suggestions
- ✅ **Metadata object** can contain new keys
- ✅ **Enum values can expand** (e.g., new severity levels added)

**Breaking changes require major version increment (1.0 → 2.0)**:

- ❌ Changing field types (string → integer)
- ❌ Making optional fields required
- ❌ Removing fields from required array
- ❌ Renaming fields
- ❌ Changing enum semantics

### Current Version History

| Version | Date | Status | Highlights |
|---------|------|--------|-----------|
| 1.0 | 2026-03-16 | Stable | Initial release with findings, summary, metadata, tracing |
| 1.1 | Planned | - | Will add support for policies, custom metadata templates, rule configurations |
| 1.2 | Planned | - | Will add support for remediation actions, webhook callbacks |
| 2.0 | Future | - | Breaking changes TBD, redesigned for performance at scale |

---

## 2. API Versioning Strategy

### Request Header API Versioning

SaaS platform ingestion APIs use the `Accept` header for version negotiation:

```http
GET /api/v1/reports/ingest
Accept: application/vnd.queryguard.v1+json
```

| Header Value | Meaning | Behavior |
|---|---|---|
| `application/vnd.queryguard.v1+json` | Explicitly request v1 | Returns v1 schema, errors on breaking changes |
| `application/vnd.queryguard.latest+json` | Latest available | Returns newest version (⚠️ use with caution) |
| `application/json` | Default/legacy | Returns v1 for backward compatibility |

### Deprecation Warnings

The API includes deprecation metadata in responses:

```json
{
  "report_version": "1.0",
  "_deprecation": {
    "sunset_date": "2027-03-16",
    "message": "Report version 1.0 will be sunset on 2027-03-16. Please upgrade to v1.1",
    "migration_guide": "https://docs.queryguard.example.com/upgrade-1.0-to-1.1"
  }
}
```

### Version Negotiation Rules

**For CLI Output (no negotiation)**:
```bash
queryguard analyze db/migrate --format json
# Always outputs current stable version (currently 1.0)
```

**For SaaS API Ingestion (with negotiation)**:
```bash
curl -H "Accept: application/vnd.queryguard.v1+json" \
  https://api.queryguard.example.com/v1/reports
# Returns only compatible reports, rejects incompatible versions
```

---

## 3. Backward Compatibility Guarantee

### What We Guarantee

✅ **Field additions are safe for deserialization**:
```json
// v1.0
{ "id": "abc123", "severity": "error" }

// v1.1 (backwards compatible)
{ "id": "abc123", "severity": "error", "new_field": "value" }
```

Consumers using json parsing will still work:
```ruby
report["severity"]  # ✅ Still works
report["new_field"] # ✅ Safe to check with dig()
```

✅ **New enum values are handled gracefully**:
```ruby
# v1.0: severity in ["critical", "error", "warn", "info"]
# v1.1: adds "security" severity level

# Robust parsing handles unknown severities:
severity = finding["severity"] # Could be "security" in v1.1
if ["critical", "error"].include?(severity)
  # Handle critical errors
end
# Unknown severities don't crash
```

✅ **Optional fields remain optional**:
```ruby
# threshold is optional, only present in check reports
source[:threshold]  # Safe to access with [], returns nil if missing
```

### What We Don't Guarantee

❌ **Positional array indexing**:
```ruby
findings[0]["metadata"]["keys"][0]  # Don't rely on array order
```

Use named access instead:
```ruby
findings[0]["metadata"]["table_name"]  # ✅ Safe
```

❌ **Private fields** (starting with `_`):
```ruby
report["_internal_timestamp"]  # May change without notice
```

❌ **Null vs missing** distinction:
```ruby
# These are equivalent for consumers:
{ "field": null }
{}
```

---

## 4. Deprecation Policy

### Timeline

**Active** (current version):
- Full support, new features added
- Example: v1.0 from launch until v1.1 release

**Sunset Warning** (18 months before discontinuation):
- Deprecation warnings in response headers & body
- Support continues, but upgrade encouraged
- Migration guides published

**Discontinued** (after sunset date):
- API rejects requests for discontinued version
- Old SDKs may need updates
- Support moved to forums/community

### Example: v1.0 Sunset Timeline

```
2026-03-16: v1.0 released (stable)
            ↓
2027-09-16: v1.1 released, v1.0 marked for sunset (2028-09-16)
            ↓
2028-09-16: v1.0 discontinued
            API.request version=1.0 → 410 Gone
```

---

## 5. Extension Points

### Custom Metadata

Finding metadata is unrestricted (but must be JSON-safe):

```json
{
  "id": "abc123",
  "rule": "remove_column",
  "metadata": {
    "table_name": "users",
    "custom_risk_score": 8.5,
    "data_classification": "pii",
    "owner_team": "backend",
    "remediation_budget": 40000
  }
}
```

Platforms can extend without breaking schema:
- Custom scoring systems
- Integration with external risk tools
- RBAC metadata (team, owner, product)
- Cost/budget tracking
- Automation hints

### Plugin Architecture (Future: v1.1+)

Planned extension points for query_guard plugin ecosystem:

```json
{
  "report_version": "1.1",
  "findings": [...],
  "plugins": {
    "security_analyzer": {
      "version": "1.0",
      "findings": [...]
    },
    "compliance_checker": {
      "version": "2.1",
      "violations": [...]
    }
  }
}
```

---

## 6. Integration Patterns

### Pattern 1: Synchronous API Ingestion

```
┌─────────────┐
│   Client    │ POST /api/v1/reports
│  (CI/Tool)  │ Accept: application/vnd.queryguard.v1+json
└──────┬──────┘
       │
       ├─ 200 OK { report_id, created_at }
       ├─ 400 Bad Request { errors: [...] }
       └─ 409 Conflict { duplicate: true }
           (Idempotency via request_id in tracing)
```

### Pattern 2: Batch Ingestion

```
POST /api/v1/batch
Accept: application/vnd.queryguard.batch+json

{
  "batch_id": "batch-abc123",
  "reports": [
    { report_version: "1.0", ... },
    { report_version: "1.0", ... }
  ]
}

200 OK {
  "batch_id": "batch-abc123",
  "processed": 2,
  "errors": 0
}
```

### Pattern 3: Webhook Delivery

```
POST https://customer.example.com/webhooks/queryguard
X-QueryGuard-Signature: sha256=...
X-QueryGuard-Delivery-ID: webhook-12345
X-QueryGuard-Timestamp: 2026-03-16T14:30:00Z

{
  "event": "report.completed",
  "report": { report_version: "1.0", ... }
}
```

### Pattern 4: Streaming (Future)

```
GET /api/v1/stream
Accept: text/event-stream

event: report_start
data: { report_id: ... }

event: finding
data: { id: "abc123", severity: "error" }

event: report_end
data: { total_findings: 42 }
```

---

## 7. Error Handling

### Validation Errors

```json
{
  "error": "schema_validation_failed",
  "request_id": "req-abc123",
  "details": [
    {
      "path": "$.findings[0].severity",
      "message": "Unrecognized severity 'critical' for version 1.0"
    }
  ]
}
```

### Version Mismatch

```json
{
  "error": "version_unsupported",
  "requested_version": "2.0",
  "available_versions": ["1.0", "1.1"],
  "migration_guide": "https://docs.queryguard.example.com/upgrade"
}
```

---

## 8. Security Considerations

### Data Classification

Reports contain sensitive information:

- **Database schema** (table names, column names)
- **Risk assessments** (data loss implications)
- **File paths** (codebase structure)

**Platform Responsibility**:
- Encrypt in transit (HTTPS/TLS 1.3+)
- Encrypt at rest (AES-256)
- Audit access logs
- Implement RBAC
- Expire old reports per retention policy

### API Authentication

```http
GET /api/v1/reports
Authorization: Bearer <api_token>
X-API-Version: 1.0
```

- Use API tokens (not passwords)
- Implement key rotation quarterly
- Rate limit per API key
- Log all access

---

## 9. Testing & Validation

### For Consumers

**Validate report_version**:
```python
def validate_queryguard_report(report):
    version = report.get('report_version', '1.0')
    major = int(version.split('.')[0])
    
    if major > 1:
        raise ValueError(f"Unsupported major version {major}")
    
    # Process report...
```

**Use JSONSchema validation**:
```bash
# Validate against schema
python -m jsonschema -i report.json docs/json-schema-report-v1.0.json
```

### For Query Guard Platform

**Integration tests**:
- ✅ Ingest v1.0 reports
- ✅ Reject reports with missing required fields
- ✅ Accept reports with new optional fields from v1.1
- ✅ Return 410 Gone for discontinued versions
- ✅ Include deprecation warnings in responses

---

## 10. Roadmap

### v1.1 (Next, ~6 months)

- Policy objects for rule customization
- Rule configuration serialization
- Custom metadata templates
- Enhanced threat scoring

### v1.2 (Later, ~12 months)

- Remediation action suggestions
- Webhook callback status
- Cost/SLA impact assessments

### v2.0 (Breaking, ~18 months)

- Redesigned for high-volume ingestion
- Query result sampling
- Streaming ingestion
- Advanced filtering in API responses

---

## Appendix: Migration Example

### Upgrading from v1.0 to v1.1

**Before (v1.0)**:
```ruby
report = JSON.parse(api_response)
report["report_version"]  # "1.0"
report["findings"][0]["metadata"]  # { table_name: "users" }
```

**After (v1.1)**:
```ruby
report = JSON.parse(api_response)
report["report_version"]  # "1.1"
report["findings"][0]["metadata"]  # { table_name: "users", policy: {...} }

# Safely handle new field:
policy = report["findings"][0].dig("metadata", "policy")
if policy
  apply_policy(policy)
end
```

**No code changes required** - v1.1 is backward compatible.

---

## Support & Questions

- **Documentation**: https://docs.queryguard.example.com
- **API Reference**: https://api.queryguard.example.com/docs
- **Status Page**: https://status.queryguard.example.com
- **Issues**: https://github.com/queryguard/platform/issues
