# Index Suggestion Feature

## Overview

QueryGuard can now automatically suggest PostgreSQL indexes for queries that exhibit missing index risk patterns. The feature analyzes query structure and EXPLAIN plans to recommend practical index statements that could improve performance.

## Key Principles

1. **Conservative**: Only suggests indexes when patterns are reasonably confident
2. **Explainable**: Includes explanation and confidence levels for each suggestion
3. **Practical**: Focuses on common patterns (WHERE clauses, ORDER BY, composite filters)
4. **Rails-aware**: Understands typical Rails query patterns, Devise auth queries, timestamp filtering, soft deletes

## Module Architecture

### PatternExtractors (`lib/query_guard/suggest/pattern_extractors.rb`)

Extracts SQL patterns from query text for index recommendation analysis.

```ruby
require "query_guard/suggest/pattern_extractors"

extractor = QueryGuard::Suggest::PatternExtractors.new

# Extract WHERE clause columns
sql = "SELECT * FROM users WHERE email = 'test@example.com' AND status = 'active'"
extractor.extract_where_columns(sql)
# => ["email", "status"]

# Extract ORDER BY columns
sql = "SELECT * FROM posts ORDER BY created_at DESC"
extractor.extract_order_by_columns(sql)
# => ["created_at"]

# Extract table name
sql = "SELECT * FROM users WHERE id = 1"
extractor.extract_table_name(sql)
# => "users"

# Extract all patterns
result = extractor.extract_all_columns(sql)
# => { where_columns: ["id"], order_by_columns: [] }
```

**Supported Patterns:**

- **WHERE clause**: Simple equality (=), comparison (<, >, <=, >=), IN, LIKE operators
- **ORDER BY**: Single and multiple columns with ASC/DESC modifiers
- **Table names**: Simple, schema-qualified (public.users), first table in JOINs

**Conservative Approach:**

- Skips function calls: `DATE(created_at) = ...` → no extraction
- Skips IS NULL/IS NOT NULL operators
- Skips BETWEEN clauses
- Stops at clause boundaries (GROUP BY, HAVING, ORDER BY, LIMIT)
- Filters out SQL keywords as false positives

### IndexSuggester (`lib/query_guard/suggest/index_suggester.rb`)

Generates practical CREATE INDEX suggestions from pattern analysis.

```ruby
require "query_guard/suggest/index_suggester"

suggester = QueryGuard::Suggest::IndexSuggester.new
```

#### suggest_for_sequential_scan

For sequential scans on filtered data (EXPLAIN shows Seq Scan with filter):

```ruby
sql = "SELECT * FROM users WHERE email = 'test@example.com'"
suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "users")

# Returns:
# {
#   suggested_index_sql: "CREATE INDEX idx_users_email ON users (email);",
#   explanation: "Index on email column for WHERE clause equality",
#   confidence: :high,
#   columns: ["email"],
#   index_name: "idx_users_email",
#   table_name: "users"
# }
```

**When to use:**
- Query shows sequential table scan followed by filter
- Common in filtered queries without indexes
- High confidence: direct column equality is reliably beneficial

#### suggest_for_expensive_sort

For expensive sorts (EXPLAIN shows Sort with high row count):

```ruby
sql = "SELECT * FROM events ORDER BY created_at DESC LIMIT 10"
suggestion = suggester.suggest_for_expensive_sort(sql, table_name: "events")

# Returns:
# {
#   suggested_index_sql: "CREATE INDEX idx_events_created_at_desc ON events (created_at DESC);",
#   explanation: "Index on created_at column for ORDER BY clause",
#   confidence: :medium,
#   columns: ["created_at"],
#   index_name: "idx_events_created_at_desc",
#   table_name: "events"
# }
```

**When to use:**
- Query sorts large result set without index
- Can significantly improve large result pagination
- Medium confidence: benefit depends on result set size

#### suggest_for_complex_filter

For multi-column equality filters (multiple WHERE conditions):

```ruby
sql = "SELECT * FROM orders WHERE user_id = ? AND status = 'pending'"
suggestion = suggester.suggest_for_complex_filter(sql, table_name: "orders")

# Returns:
# {
#   suggested_index_sql: "CREATE INDEX idx_orders_user_id_status ON orders (user_id, status);",
#   explanation: "Composite index on user_id, status columns for WHERE clause",
#   confidence: :medium,
#   columns: ["user_id", "status"],
#   index_name: "idx_orders_user_id_status",
#   table_name: "orders"
# }
```

**When to use:**
- Query filters on 2-3 columns with AND conditions
- Column order follows where clause order
- Medium confidence: benefit depends on selectivity

**Conservative Limit:** Only suggests for 2-3 columns (max 3)

#### suggest_for_join

For join condition indexes (missing index on join key):

```ruby
suggestion = suggester.suggest_for_join("user_id", table_name: "orders")

# Returns:
# {
#   suggested_index_sql: "CREATE INDEX idx_orders_user_id ON orders (user_id);",
#   explanation: "Index on user_id column for JOIN condition",
#   confidence: :high,
#   columns: ["user_id"],
#   index_name: "idx_orders_user_id",
#   table_name: "orders"
# }
```

**When to use:**
- Foreign key join conditions without index
- Common performance bottleneck
- High confidence: join indexes are almost always beneficial

#### build_recommendation_text

Creates user-facing recommendation with important disclaimers:

```ruby
suggestion = suggester.suggest_for_sequential_scan(
  "SELECT * FROM users WHERE email = ?",
  table_name: "users"
)

text = suggester.build_recommendation_text(suggestion)
# Returns formatted text with:
# - SQL statement to copy/paste
# - Confidence level
# - IMPORTANT disclaimers about testing first
# - Selectivity verification steps
# - Action items for DBA review
```

## Integration with ExplainEnricher

The index suggestion feature automatically integrates with `ExplainEnricher` to enrich findings with suggested indexes:

```ruby
adapter = QueryGuard::Explain::PostgreSQLAdapter.new(connection)
enricher = QueryGuard::Explain::ExplainEnricher.new(adapter)

findings = enricher.enrich([], "SELECT * FROM users WHERE email = ?")

finding = findings.first
# Now includes metadata:
# {
#   type: :sequential_scan,
#   metadata: {
#     table_name: "users",
#     suggested_index_sql: "CREATE INDEX idx_users_email ON users (email);",
#     suggested_index_columns: ["email"],
#     suggested_index_confidence: :high,
#     suggested_index_name: "idx_users_email",
#     description: "..."
#   }
# }
```

### Enhanced Finding Types

1. **Sequential Scan** - Adding index can eliminate table scan
2. **Missing Index** - Filter-based index candidate
3. **Expensive Sort** - ORDER BY index suggestion

## Real-World Examples

### Rails User Model Query

```ruby
# Query
User.where(email: 'test@example.com').first

# Extracted patterns
# WHERE: ["email"]
# Table: "users"

# Suggested index
CREATE INDEX idx_users_email ON users (email);
```

### Rails Post Model with Pagination

```ruby
# Query
Post.where(user_id: 123).order(created_at: :desc).limit(10)

# Extracted patterns
# WHERE: ["user_id"]
# ORDER BY: ["created_at"]
# Table: "posts"

# Suggested indexes
CREATE INDEX idx_posts_user_id ON posts (user_id);
CREATE INDEX idx_posts_created_at_desc ON posts (created_at DESC);
```

### Rails Devise Auth Query

```ruby
# Query
User.find_by(email: 'test@example.com')
# Becomes: SELECT * FROM users WHERE email = ?

# Extracted patterns
# WHERE: ["email"]
# Table: "users"

# Suggested index
CREATE INDEX idx_users_email ON users (email);
```

### Soft-Delete Query (Rails Paranoia)

```ruby
# Query
Comment.where(post_id: 42).where(deleted_at: nil)
# Becomes: SELECT * FROM comments WHERE post_id = ? AND deleted_at IS NULL

# Pattern extraction
# WHERE: ["post_id"]  (IS NULL not extracted - conservative)
# Table: "comments"

# Suggested index
CREATE INDEX idx_comments_post_id ON comments (post_id);
```

## Confidence Levels

### High Confidence (:high)

- Simple WHERE clause equality on single column
- Join condition on foreign key
- When pattern is unambiguously beneficial

**Example:** `WHERE email = ?` → High confidence

### Medium Confidence (:medium)

- Multi-column composite filters
- ORDER BY on large result sets
- When benefit depends on data characteristics

**Example:** `WHERE status = ? AND type = ?` → Medium confidence

### Low Confidence (:low)

- Complex expressions
- Functions in WHERE
- When pattern suggests possible benefit but very uncertain

## Best Practices

### 1. Test Recommendations First

Always test in development/staging before production:

```bash
# 1. Create index on test environment
CREATE INDEX idx_users_email ON users (email);

# 2. Run EXPLAIN ANALYZE on representative queries
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'test@example.com';

# 3. Verify query timing improvement
# 4. Check index size impact
```

### 2. Verify Selectivity

Index is only beneficial if it filters columns effectively:

```sql
-- Check column cardinality (how many distinct values)
SELECT COUNT(DISTINCT email) FROM users;  -- For cardinality
SELECT COUNT(*) FROM users;                -- For total rows
-- Index beneficial if cardinality is reasonably close to total rows
```

### 3. Monitor Query Selectivity

```ruby
# Use EXPLAIN to verify index is actually being used
EXPLAIN SELECT * FROM users WHERE email = 'test@example.com';
# Should show "Index Scan" not "Seq Scan"
```

### 4. Consider Performance Impact

- New indexes consume disk space
- INSERT/UPDATE/DELETE operations must also update indexes
- Total table size and index overhead should be acceptable
- May affect query planning time

### 5. Follow Column Ordering

For composite indexes, put most selective column first:

```sql
-- If email has higher cardinality than status
-- Put email first
CREATE INDEX idx_users_email_status ON users (email, status);

-- Better selectivity → faster filtering
```

## Testing

Comprehensive test suite with 83+ assertions:

```bash
# Run pattern extractor tests (45 tests)
rspec spec/suggest/pattern_extractors_spec.rb

# Run index suggester tests (38 tests)
rspec spec/suggest/index_suggester_spec.rb

# Run all suggest tests
rspec spec/suggest
```

**Test Coverage:**
- Pattern extraction from various SQL patterns
- Common Rails query examples
- Edge cases (quoted identifiers, functions, complex expressions)
- Metadata structure validation
- Recommendation text formatting
- Confidence level assignment

## Limitations & Known Issues

1. **Function calls**: Conservatively doesn't extract columns from function calls
   - `DATE(created_at) = '2024-01-01'` → No extraction

2. **IS NULL / IS NOT NULL**: These operators are not extracted
   - `deleted_at IS NULL` → Not extracted (requires different index strategy)

3. **Complex expressions**: Skips BETWEEN, OR conditions, CASE statements

4. **Quoted identifiers**: Conservative approach for non-standard identifiers

5. **Statistical approach**: Doesn't have access to actual table statistics for cardinality

## Integration with Risk Analysis

Index suggestions complement the QueryGuard risk analysis:

```ruby
# Risk level identifies missing index problem
risk = QueryGuard::Analysis::RiskDetectors::MissingIndexDetector.new
findings = risk.detect(query, config)

# Enricher provides actionable suggestion
enricher = QueryGuard::Explain::ExplainEnricher.new(adapter)
enriched = enricher.enrich(findings, query)

# Result: Finding with both risk and actionable suggestion
enriched.first.metadata[:suggested_index_sql]
```

## Future Enhancements

Possible improvements for future releases:

1. **Selectivity Analysis**: Integrate with PostgreSQL table statistics
2. **Index Impact Simulation**: Estimate query time improvement
3. **Index Consolidation**: Suggest consolidating multiple indexes
4. **Covering Indexes**: Suggest columns for index covering
5. **Partial Indexes**: Recommend WHERE conditions for selective indexes
6. **Multi-table Suggestions**: JOINs with multiple tables
7. **View Support**: Index recommendations for queries on views

## API Reference

See [EXPLAIN_INTEGRATION.md](EXPLAIN_INTEGRATION.md) for complete ExplainEnricher API reference.

## Related Documentation

- [EXPLAIN_INTEGRATION.md](EXPLAIN_INTEGRATION.md) - PostgreSQL EXPLAIN integration
- [FINDING_IMPLEMENTATION.md](FINDING_IMPLEMENTATION.md) - Finding structure and risk types
- [README.md](README.md) - QueryGuard overview
