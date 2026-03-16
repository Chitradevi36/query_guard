# QueryGuard GitHub Actions Examples

This directory contains ready-to-use GitHub Actions workflow examples for QueryGuard.

---

## Quick Choice Guide

### I want the simplest setup
→ Use **`queryguard-minimal.yml`**

- No database setup
- 25-30 seconds total
- Good for quick feedback on feature branches
- Trade-off: Misses some table-size-aware findings

### I want the most accurate checks
→ Use **`queryguard-standard.yml`**

- Includes PostgreSQL service
- 40-50 seconds total
- Best accuracy
- Recommeded for production-ready checks

### I want strict checks on main branch
→ Use **`queryguard-strict-main.yml`**

- High threshold (warn level)
- Only runs on main/master
- Catches more issues (critical + error + warning)
- Prevents risky migrations from reaching production

---

## Installation

### Option A: Use One Workflow

Choose one example above and copy it:

```bash
# Example: Copy the standard workflow
cp examples/workflows/queryguard-standard.yml .github/workflows/queryguard.yml
```

### Option B: Combine Multiple Workflows

Run quick checks on PRs, strict checks on main:

```bash
# Quick check for PRs
cp examples/workflows/queryguard-minimal.yml .github/workflows/queryguard-pr.yml

# Strict check for main
cp examples/workflows/queryguard-strict-main.yml .github/workflows/queryguard-main.yml
```

### Option C: Customize

Copy an example and modify to your needs:

```bash
cp examples/workflows/queryguard-standard.yml .github/workflows/queryguard.yml
# Edit as needed
```

---

## Comparison

| Aspect | Minimal | Standard | Strict |
|--------|---------|----------|--------|
| **Speed** | 25-30s | 40-50s | 40-50s |
| **Database** | None | PostgreSQL 14 | PostgreSQL 14 |
| **Accuracy** | Good | Excellent | Excellent |
| **Threshold** | error | error | warn |
| **Use Case** | PRs | Production | Main branch |
| **File Size** | 22 lines | 80 lines | 70 lines |

---

## Thresholds Explained

### `--threshold error` (Default in Minimal/Standard)
Blocks when:
- ❌ Critical findings detected
- ❌ Error-level findings detected
- ✅ Warnings allowed (doesn't block)

Good for: Feature branches, PRs

### `--threshold warn` (Strict)
Blocks when:
- ❌ Critical findings detected
- ❌ Error-level findings detected
- ❌ Warning-level findings detected
- ✅ Info-only findings allowed

Good for: Main branch, pre-production

### `--threshold critical` (Permissive)
Blocks only critical findings.  
Good for: Legacy systems, high-velocity teams

---

## Step-by-Step Setup

### 1. Choose Your Workflow

Most teams should start with **Minimal** (fast feedback) then move to **Standard** (accuracy) after testing.

### 2. Copy to Your Repository

```bash
mkdir -p .github/workflows
cp examples/workflows/queryguard-minimal.yml .github/workflows/queryguard.yml
```

### 3. Add to Gemfile

```ruby
# Gemfile
group :development, :test do
  gem 'query_guard'
end
```

Run:
```bash
bundle install
```

### 4. Commit and Push

```bash
git add .github/workflows/queryguard.yml Gemfile Gemfile.lock
git commit -m "Add QueryGuard migration safety check"
git push
```

### 5. Create a Test PR

Edit a migration file or create a new one:

```bash
git checkout -b test/query-guard
# Make a migration change
git add db/migrate/
git commit -m "Test migration"
git push origin test/query-guard
```

Open a PR. The workflow runs automatically! ✅

---

## Customization

### Change the Threshold

In any workflow, modify:

```yaml
- run: bundle exec queryguard check db/migrate --threshold error
```

Change `error` to:
- `critical` (permissive)
- `warn` (strict)
- `info` (maximum)

### Add to Specific Branches

```yaml
on:
  push:
    branches:
      - main
      - develop
```

### Run on All Files

Remove the `paths` section to run on every commit:

```yaml
on:
  push:
    branches:
      - main
# Remove this:
# paths:
#   - 'db/migrate/**'
```

### Skip on Certain Commits

Add skip phrase to commit message:

```bash
git commit -m "Hotfix [skip migrations]"
```

(You'll need to add this to the workflow)

---

## Real-World Examples

### Example 1: PR + Main Branch

**For feature branches**: Fast checks (`minimal`)  
**For main branch**: Strict checks (`strict`)

Setup:
```bash
cp examples/workflows/queryguard-minimal.yml .github/workflows/queryguard-pr.yml
cp examples/workflows/queryguard-strict-main.yml .github/workflows/queryguard-main.yml
```

Edit `queryguard-pr.yml` to trigger on `pull_request`:
```yaml
on:
  pull_request:
    paths: ['db/migrate/**']
```

Leave `queryguard-main.yml` as-is (triggers on push to main).

### Example 2: Single Comprehensive Workflow

Use `standard.yml` for all scenarios:
```bash
cp examples/workflows/queryguard-standard.yml .github/workflows/queryguard.yml
```

Triggers on both PRs and main pushes. Single source of truth.

### Example 3: Phased Rollout

Week 1: Report only (no blocking)
```yaml
- run: bundle exec queryguard check db/migrate || true
```

Week 2+: Block on failures
```yaml
- run: bundle exec queryguard check db/migrate
```

---

## Troubleshooting

### Workflow doesn't run

Check:
1. Is `.github/workflows/queryguard.yml` committed? (Not gitignored)
2. Does your commit touch `db/migrate/` files or other trigger paths?
3. Check "Actions" tab in your GitHub repo

### "Ruby version not found"

Most common issue. Fix:

Option A: Create `.ruby-version` file
```bash
echo "3.1.0" > .ruby-version
git add .ruby-version
```

Option B: Hard-code in workflow
```yaml
with:
  ruby-version: 3.1.0  # Change to your version
```

### "queryguard command not found"

Fix:
1. Verify `Gemfile` has `gem 'query_guard'`
2. Verify `bundler-cache: true` in setup-ruby
3. Check `Gemfile.lock` is committed

### "Database connection refused"

Fix:
1. Add health check delay:
```yaml
- run: sleep 5  # Wait for PostgreSQL to be ready
```

2. Or use minimal example (no database)

---

## Next Steps

1. **Choose a workflow** from the options above
2. **Copy to `.github/workflows/`**
3. **Add `gem 'query_guard'` to Gemfile**
4. **Commit and push**
5. **Test with a PR** (create a test branch)
6. **Enable branch protection** (Settings → Branches)

---

## Support

- **General setup**: See [../docs/GITHUB_ACTIONS_SETUP.md](../docs/GITHUB_ACTIONS_SETUP.md)
- **Command reference**: See [../CI_CHECK_QUICK_REFERENCE.md](../CI_CHECK_QUICK_REFERENCE.md)
- **Deep dive**: See [../CI_CHECK_GUIDE.md](../CI_CHECK_GUIDE.md)

---

## Performance

| Workflow | Setup | Check | Total |
|----------|-------|-------|-------|
| Minimal | 20s | 5s | 25s |
| Standard | 30s | 10s | 40s |
| Strict | 30s | 10s | 40s |

All are fast. Choose based on accuracy needs, not speed.

---

**Ready to start?** Copy one of the workflows above and commit it! 🚀
