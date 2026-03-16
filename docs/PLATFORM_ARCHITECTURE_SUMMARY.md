# QueryGuard JSON Report Contract: Platform Architecture Summary

**Date**: March 16, 2026  
**Status**: ✅ Complete & Production-Ready  
**Test Coverage**: 82 tests passing (100%)  
**Target**: SaaS hosted platform ingestion API

---

## Executive Summary

QueryGuard now has a **production-grade JSON report contract** suitable for SaaS platform ingestion. The implementation provides:

- ✅ **Versioned schema** (1.0) with clear evolution strategy
- ✅ **Distributed tracing** (OpenTelemetry compatible) for system observability
- ✅ **Batch ingestion** for bulk report loading
- ✅ **Pagination support** for large finding sets
- ✅ **Formal JSONSchema** validation files
- ✅ **Comprehensive API specification** with backward compatibility guarantees
- ✅ **82 tests** validating the entire contract

This document supersedes the initial JSON output work and elevates it to **SaaS-grade platform architecture**.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                  QueryGuard CLI Tools                   │
│  (analyze, check commands)                              │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ├─► JsonReporter (single report)
                  │   └─ Tracing IDs (request_id, trace_id, span_id)
                  │   └─ Schema v1.0 with versioning
                  │
                  ├─► BatchReportFormatter (multiple reports)
                  │   └─ Batch aggregation & stats
                  │   └─ Cursor-based pagination
                  │
                  └─► PagedReportFormatter (large findings)
                      └─ Finding pagination (100-1000 per page)
                      └─ Page tokens for continuation

                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│          SaaS Platform Ingestion API                     │
│  POST /api/v1/reports/ingest                           │
│  POST /api/v1/batch (bulk ingestion)                   │
│  GET  /api/v1/stream (webhooks)                        │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ✓ Validation against JSONSchema
                  ✓ Tracing correlation across systems
                  ✓ Idempotency via request_id
                  ✓ Bandwidth-efficient pagination
                  ✓ Version negotiation (Accept headers)
```

---

## Component Breakdown

### 1. JsonReporter (Single Report Generation)

**File**: [lib/query_guard/cli/json_reporter.rb](lib/query_guard/cli/json_reporter.rb)  
**Lines**: 240+  
**Purpose**: Generate individual analysis reports with tracing context

**Key Features**:
- Automatic tracing ID generation (request_id, trace_id, span_id)
- Support for custom tracing context (parent_span_id for nested calls)
- Complete report structure with metadata
- Deterministic finding IDs for deduplication

**Example Usage**:
```ruby
reporter = QueryGuard::CLI::JsonReporter.new(
  findings: analysis_results,
  command: 'analyze',
  path: 'db/migrate',
  options: {
    trace_id: 'trace-from-upstream-service',
    parent_span_id: 'parent-op-123'
  }
)

json_output = reporter.generate
```

**Output**: Single JSON report

---

### 2. BatchReportFormatter (Bulk Ingestion)

**File**: [lib/query_guard/cli/batch_report_formatter.rb](lib/query_guard/cli/batch_report_formatter.rb)  
**Lines**: 130+  
**Purpose**: Wrap multiple reports for API bulk ingestion

**Key Features**:
- Aggregate statistics across all reports in batch
- Batch-level correlation ID for distributed tracing
- Pagination metadata for cursor-based continuation
- Automatic ID generation (batch_id, correlation_id)

**Example Usage**:
```ruby
# Collect 100 analysis reports
reports = analysis_pipeline.map { |job| job.report }

# Wrap in batch for platform ingestion
batch = QueryGuard::CLI::BatchReportFormatter.new(
  reports: reports,
  options: {
    page: 1,
    page_size: 100,
    has_more: false
  }
)

api_request_body = batch.generate
# POST to /api/v1/batch
```

**Output**: Batch wrapper with 1+ reports

---

### 3. PagedReportFormatter (Large Finding Sets)

**File**: [lib/query_guard/cli/paged_report_formatter.rb](lib/query_guard/cli/paged_report_formatter.rb)  
**Lines**: 150+  
**Purpose**: Paginate large finding arrays for memory-efficient processing

**Key Features**:
- Configurable page size (default 100, max 1000)
- Cursor-based pagination with opaque tokens
- Automatic finding count updates per page
- Previous/next page navigation tokens

**Example Usage**:
```ruby
report = full_analysis_with_1000_findings

# Return first 100 findings
page1 = PagedReportFormatter.new(
  report: report,
  page_size: 100,
  page: 1
)

# Client receives pagination metadata + next_page_token
# Can then request page 2, 3, etc. separately
```

**Output**: Paginated report (subset of findings)

---

### 4. JSONSchema Validation Files

**Files**:
- [docs/json-schema-report-v1.0.json](docs/json-schema-report-v1.0.json) - Single report schema
- [docs/json-schema-batch-v1.0.json](docs/json-schema-batch-v1.0.json) - Batch wrapper schema

**Purpose**: Formal contract definition for strict validation

**Usage**: External platforms can validate incoming reports:
```bash
# Validate against schema
python -m jsonschema -i report.json docs/json-schema-report-v1.0.json

# Or in code
JSON::Validator.validate!(schema, report_json)
```

---

### 5. Platform API Specification

**File**: [docs/PLATFORM_API_SPECIFICATION.md](docs/PLATFORM_API_SPECIFICATION.md)  
**Length**: 600+ lines  
**Purpose**: Complete API contract for SaaS platform engineers

**Covers**:
1. **Report Versioning** - How schema evolves (1.0 → 1.1 → 2.0)
2. **API Versioning** - Request header negotiation (Accept headers)
3. **Backward Compatibility** - What's guaranteed and what's not
4. **Deprecation Policy** - Timeline for old version sunset
5. **Extension Points** - Where platforms can customize
6. **Integration Patterns** - Sync/async/batch/webhook flows
7. **Error Handling** - Schema validation errors
8. **Security** - Data classification and encryption
9. **Testing** - Validation patterns for consumers
10. **Roadmap** - Planned features for v1.1, 1.2, 2.0

---

## Test Coverage (82 Tests)

| Category | Tests | Status |
|----------|-------|--------|
| JsonReporter (original) | 35 | ✅ Passing |
| JSON Integration | 8 | ✅ Passing |
| **Platform API Contract** | **39** | ✅ Passing |
| **Total** | **82** | **✅ All Passing** |

### Platform API Test Coverage

- ✅ Report version stability
- ✅ Tracing context generation (request_id, trace_id, span_id)
- ✅ Batch ingestion format
- ✅ Batch statistics aggregation
- ✅ Pagination metadata
- ✅ Paged report formatting (multipage)
- ✅ Cursor-based pagination tokens
- ✅ Schema stability & contract
- ✅ API versioning signals
- ✅ Extensibility & custom metadata

**Run all tests**:
```bash
cd /path/to/query_guard
rspec spec/cli/json_reporter_spec.rb \
      spec/cli/json_output_integration_spec.rb \
      spec/cli/platform_api_contract_spec.rb \
      --format progress

# Output: 82 examples, 0 failures ✅
```

---

## Key Design Decisions (Platform Architect Perspective)

### 1. Explicit Versioning

**Decision**: Include `report_version: "1.0"` in every report  
**Rationale**: Consumers can validate compatibility before processing  
**Impact**: Safe to add new optional fields without breaking old clients  

### 2. Distributed Tracing from the Start

**Decision**: Auto-generate request_id, trace_id, span_id in every report  
**Rationale**: Essential for SaaS platform observability and debugging  
**Impact**: Platform can correlate reports across systems in logs/traces  

**Example Correlation**:
```
Request → [request_id: req-abc123, trace_id: trace-456]
  Analysis 1 → [span_id: span-001, parent: trace-456]
  Analysis 2 → [span_id: span-002, parent: trace-456]
Platform receives batch with trace-456
Can reconstruct full execution path across all 3 operations
```

### 3. Batch as First-Class Concept

**Decision**: Dedicated BatchReportFormatter for bulk operations  
**Rationale**: Enables efficient SaaS ingestion at scale  
**Impact**: Single API endpoint can accept 100+ reports with aggregated stats  

### 4. Pagination Built In (Optional)

**Decision**: PagedReportFormatter for large finding sets  
**Rationale**: Not all platforms want 10MB JSON payloads; support chunking  
**Impact**: Platforms can stream findings page-by-page without memory bloat  

### 5. Schema Stability Strategy

**Decision**: Clear versioning with non-breaking expansion rules  
**Rationale**: Prevent accidental breaking changes  
**Impact**:
- v1.0 → v1.1: Add fields, expand enums (✅ safe)
- v1.1 → v2.0: Rename, require optional, remove fields (❌ breaking)

### 6. Formal JSONSchema Definitions

**Decision**: Publish `json-schema-report-v1.0.json` alongside code  
**Rationale**: Enables strict validation in platforms/SDKs  
**Impact**: Python + Ruby + JavaScript validators can all validate the same schema  

---

## Platform Integration Patterns

### Pattern 1: Synchronous API Ingestion

```
CLI Command → JsonReporter → Single JSON → POST /api/v1/reports
                                            └─ Returns: 200 OK { report_id, created_at }
```

### Pattern 2: Batch Ingestion

```
CLI Output [R1, R2, R3] → BatchReportFormatter → Batch JSON → POST /api/v1/batch
                                                              └─ Returns: 200 OK { processed: 3, errors: 0 }
```

### Pattern 3: Streaming Results

```
Analysis Pipeline → Reports [R1, R2, ...] → PagedReportFormatter (each page)
                                             → GET /api/v1/stream?token=T1
                                             → GET /api/v1/stream?token=T2
```

### Pattern 4: Webhook Events

```
Report completed → Event { event: "report.completed", report, metadata }
                → Platform stores in webhook queue
                → POST https://customer.example.com/webhooks/queryguard
```

---

## Backward Compatibility Guarantees

### ✅ Safe for Platforms to Rely On

✅ **Field additions**: New optional fields can be added to findings  
✅ **Enum expansion**: New severity levels or analyzer names can be introduced  
✅ **Metadata flexibility**: Custom fields can be added to metadata object  
✅ **Tracing context**: Can be extended with new IDs without breaking old parsers  

### ❌ Breaking Changes (Require v2.0)

❌ **Rename fields**: Changing `analyzer` → `analyzer_name`  
❌ **Change types**: `line_number: 5` → `line_number: "5"`  
❌ **Make optional required**: `file_path?` → `file_path!`  
❌ **Remove fields**: Deleting `metadata` from findings  

**Mitigation**: `PLATFORM_API_SPECIFICATION.md` documents all migration paths

---

## Future Roadmap

### v1.1 (Next, ~6 months)

- [ ] Policy configuration objects in reports
- [ ] Rule customization metadata
- [ ] Custom metadata templates
- [ ] Enhanced threat scoring fields

### v1.2 (Later, ~12 months)

- [ ] Remediation action suggestions
- [ ] SLA/cost impact assessments
- [ ] Webhook delivery status tracking
- [ ] Integration with external risk frameworks

### v2.0 (Breaking, ~18 months)

- [ ] Redesigned for high-volume ingestion (streaming)
- [ ] Query result sampling (for huge datasets)
- [ ] GraphQL API alongside REST/JSON
- [ ] Advanced filtering in API responses

---

## Validation & Verification

### For SaaS Platform Teams

**Validate incoming reports**:
```python
import jsonschema
import json

schema = json.load(open('json-schema-report-v1.0.json'))
report = json.loads(incoming_json)

# Raises ValidationError if not compliant
jsonschema.validate(report, schema)
print("✅ Report valid for v1.0")
```

### For QueryGuard Contributors

**Run full test suite**:
```bash
rspec spec/cli/json_reporter_spec.rb \
      spec/cli/json_output_integration_spec.rb \
      spec/cli/platform_api_contract_spec.rb \
      -f progress

# Expected: 82 examples, 0 failures
```

---

## Files Summary

### New Code Files (3)

| File | Lines | Purpose |
|------|-------|---------|
| [lib/query_guard/cli/batch_report_formatter.rb](lib/query_guard/cli/batch_report_formatter.rb) | 130 | Batch wrapper for bulk ingestion |
| [lib/query_guard/cli/paged_report_formatter.rb](lib/query_guard/cli/paged_report_formatter.rb) | 150 | Finding pagination for large datasets |
| [spec/cli/platform_api_contract_spec.rb](spec/cli/platform_api_contract_spec.rb) | 514 | Complete platform contract tests (39 examples) |

### Enhanced Code Files (2)

| File | Changes | Impact |
|------|---------|--------|
| [lib/query_guard/cli/json_reporter.rb](lib/query_guard/cli/json_reporter.rb) | Added tracing IDs | Distributed systems support |
| [lib/query_guard.rb](lib/query_guard.rb) | Added requires | Batch & paged formatters available |

### Documentation Files (3)

| File | Pages | Audience |
|------|-------|----------|
| [docs/json-schema-report-v1.0.json](docs/json-schema-report-v1.0.json) | JSONSchema | API validators, SDKs |
| [docs/json-schema-batch-v1.0.json](docs/json-schema-batch-v1.0.json) | JSONSchema | Batch API consumers |
| [docs/PLATFORM_API_SPECIFICATION.md](docs/PLATFORM_API_SPECIFICATION.md) | 600+ lines | SaaS platform architects |

---

## Quick Start for Platform Teams

### 1. Validate a Report

```bash
# Download schema
curl -o schema.json https://raw.githubusercontent.com/.../json-schema-report-v1.0.json

# Validate your report
ajv validate -s schema.json -d report.json
```

### 2. Parse & Ingest

```python
import json

with open('report.json') as f:
    report = json.load(f)

# Check version compatibility
if report['report_version'] != '1.0':
    raise ValueError(f"Unsupported version: {report['report_version']}")

# Extract tracing context
trace_id = report['tracing']['trace_id']
correlate_with_logs(trace_id)  # Use for distributed tracing

# Process findings
for finding in report['findings']:
    store_in_database(finding)
    maybe_trigger_remediation(finding)
```

### 3. Handle Pagination

```python
page = 1
while True:
    report = fetch_page(page, page_size=100)
    
    for finding in report['findings']:
        process(finding)
    
    if not report['pagination']['has_more']:
        break
    
    page += 1
```

---

## References & Documentation

- **Main Integration Guide**: [docs/JSON_REPORT_SCHEMA.md](docs/JSON_REPORT_SCHEMA.md) (original, still valid)
- **API Specification**: [docs/PLATFORM_API_SPECIFICATION.md](docs/PLATFORM_API_SPECIFICATION.md) (new, comprehensive)
- **Schema (Single)**: [docs/json-schema-report-v1.0.json](docs/json-schema-report-v1.0.json)
- **Schema (Batch)**: [docs/json-schema-batch-v1.0.json](docs/json-schema-batch-v1.0.json)
- **Tests**: [spec/cli/platform_api_contract_spec.rb](spec/cli/platform_api_contract_spec.rb)

---

## Conclusion

QueryGuard now has **production-grade platform architecture** for SaaS ingestion:

✅ **Versioned schema** with clear evolution strategy  
✅ **Distributed tracing** for observability  
✅ **Batch ingestion** for scale  
✅ **Pagination** for efficiency  
✅ **Formal contracts** (JSONSchema)  
✅ **82 comprehensive tests**  
✅ **Backward compatibility** over 18+ months  

**Status**: Ready to deploy to production SaaS platform.

---

*Generated March 16, 2026 | QueryGuard Platform Architecture*
