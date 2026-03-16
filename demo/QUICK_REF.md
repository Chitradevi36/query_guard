# QueryGuard Demo - Quick Reference

## What's the Demo?

A minimal Rails app with **intentional anti-patterns** to validate QueryGuard's detection capabilities.

## Run It

```bash
cd demo
bundle install
bundle exec queryguard analyze db/migrate
```

## What You'll See

### Summary
```
🔴 CRITICAL: 1 finding (data loss)
🟡 WARN:     3 findings (performance & reliability)
🟢 INFO:     2 findings (clean)
```

### Key Findings

1. **CRITICAL** - Removing column from users table (data loss)
2. **WARN** - Adding index without CONCURRENTLY (table lock)
3. **WARN** - NOT NULL without default (migration failure)
4. **WARN** - Foreign key without index (slow queries)

## Sample Commands

### Basic Analysis
```bash
bundle exec queryguard analyze db/migrate
```

### Verbose (with recommendations)
```bash
bundle exec queryguard analyze db/migrate --verbose
```

### JSON (for processing)
```bash
bundle exec queryguard analyze db/migrate --format json
```

### Check Command (for CI)
```bash
bundle exec queryguard check db/migrate --threshold critical
# Exit 0 if OK, 1 if findings above threshold
```

### Pretty Print JSON
```bash
bundle exec queryguard analyze db/migrate --format json | jq
```

## Migrations in the Demo

| File | Severity | Issue |
|------|----------|-------|
| 01_create_users | ✅ INFO | Clean baseline |
| 02_add_posts_table | 🟡 WARN | Missing index on FK |
| 03_add_index_on_posts_content | 🟡 WARN | No CONCURRENTLY flag |
| 04_remove_phone_from_users | 🔴 CRITICAL | Data loss - no backfill |
| 05_add_comments_table | ✅ INFO | Clean baseline |
| 06_add_status_to_users | 🟡 WARN | NOT NULL without default |

## Model Anti-Patterns

- `User.select('*')` - SELECT * with all columns
- `user.posts.count` in loop - N+1 queries
- `post.get_post_summary` - Multiple +1 queries

## Perfect For

✅ Testing QueryGuard locally
✅ Recording demo videos
✅ Validating new features
✅ Marketing materials
✅ Documentation & blog posts

## Files in Demo

```
demo/
├── db/migrate/          # 6 sample migrations with issues
├── app/models/          # Example models with anti-patterns
├── Gemfile              # Dependencies
├── README.md            # Full documentation
├── DEMO_CONFIG.md       # Configuration guide
├── QUICK_REF.md         # This file
└── run_demo.sh          # Quick setup script
```

## Success Criteria

When you run the demo, expect:

✅ 1 CRITICAL finding
✅ 3+ WARNING findings  
✅ 2 INFO findings
✅ Analysis takes <500ms
✅ JSON output is valid

If you see these, QueryGuard is working correctly!

---

*Get started: `cd demo && bundle install && bundle exec queryguard analyze db/migrate`*
