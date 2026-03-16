# GitHub Actions Setup Guide for QueryGuard

This guide shows how to set up QueryGuard in GitHub Actions to automatically check database migrations for safety on every pull request.

**Time to setup**: 5 minutes  
**Difficulty**: Beginner  
**Prerequisites**: Rails project with `db/migrate/` directory

---

## Quick Start (5 minutes)

### 1. Add QueryGuard to Your Gemfile

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

### 2. Copy the Workflow File

Copy this workflow file to your repository:

**File**: `.github/workflows/queryguard.yml`

```yaml
name: QueryGuard Migration Safety Check

on:
  pull_request:
    paths:
      - 'db/migrate/**'
  push:
    branches:
      - main
      - develop

jobs:
  check:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:14-alpine
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432
    
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version
          bundler-cache: true
      
      - name: Check migrations for safety
        run: bundle exec queryguard check db/migrate
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/test_db
```

### 3. Push and Test

```bash
git add .github/workflows/queryguard.yml Gemfile Gemfile.lock
git commit -m "Add QueryGuard GitHub Actions workflow"
git push origin your-branch
```

Create a pull request. The workflow will run automatically! ✅

---

## What Happens Next

### When Migrations Are Safe ✅
- Workflow passes (green checkmark)
- PR shows "All checks passed"
- You can merge safely

### When Migrations Are Risky ❌
- Workflow fails (red X)
- PR shows "Some checks failed"
- Click "Details" to see what's risky
- Fix the migration and push again

---

## Understanding the Workflow

The workflow does three things:

### 1. Triggers
Runs on:
- **Pull requests** that touch `db/migrate/` files
- **Pushes** to main/develop branches

### 2. Environment Setup
- Spins up PostgreSQL 14 (migration checks are more accurate with a real database)
- Installs Ruby and your gems
- Creates test database

### 3. Checks
- `queryguard analyze` - Detailed analysis
- `queryguard check` - Safety gate (blocks if risky)

---

## Customization

### Change the Threshold

By default, the check blocks on **error** level findings (risky patterns).

To be stricter (also block warnings):
```yaml
- name: Check migrations for safety
  run: bundle exec queryguard check db/migrate --threshold warn
```

To be more lenient (only block critical):
```yaml
- name: Check migrations for safety
  run: bundle exec queryguard check db/migrate --threshold critical
```

**Thresholds**: `critical` < `error` (default) < `warn` < `info`

### Disable Database for Faster Checks

Remove the PostgreSQL service if you don't want database-aware checking:

```yaml
# Remove the entire 'services:' block
# Remove the 'DATABASE_URL: ...' env var

# Just run the check
- name: Check migrations for safety
  run: bundle exec queryguard check db/migrate
```

This is faster but detects fewer issues. Recommended only for small projects.

### Run on All PR Branches

By default, the workflow only runs on PRs that **change migration files**.

To run on every PR:
```yaml
on:
  pull_request:
    # Remove this section ↓
    paths:
      - 'db/migrate/**'
```

---

## Exit Codes

The workflow uses standard exit codes:

| Code | Meaning | Action |
|------|---------|--------|
| 0 | ✅ Safe to deploy | PR passes, can merge |
| 1 | ❌ Risky migrations | PR fails, fix migrations |
| 2 | ⚠️ Error running check | PR fails, check logs |

---

## Troubleshooting

### "Database connection refused"

**Problem**: PostgreSQL service didn't start.

**Solution**: Add a delay before running the check:
```yaml
- name: Wait for PostgreSQL
  run: sleep 5

- name: Check migrations
  run: bundle exec queryguard check db/migrate
```

### "Ruby version not found"

**Problem**: The `.ruby-version` file doesn't exist or has wrong version.

**Solution**: Either create the file:
```bash
echo "3.1.0" > .ruby-version
```

Or hard-code the version in the workflow:
```yaml
- uses: ruby/setup-ruby@v1
  with:
    ruby-version: 3.1.0  # Change to your version
```

### "queryguard command not found"

**Problem**: The gem wasn't installed in the workflow.

**Solution**: Verify `Gemfile` has `gem 'query_guard'` and run:
```yaml
- uses: ruby/setup-ruby@v1
  with:
    bundler-cache: true  # This line must be present
```

### "No migrations found"

**Problem**: The workflow couldn't find `db/migrate/` directory.

**Solution**: Check the path in the workflow matches your project:
```yaml
run: bundle exec queryguard check db/migrate  # ← Change this path if needed
```

---

## Local Verification

Before relying on CI, test locally:

```bash
# Install
bundle install

# Check your migrations
bundle exec queryguard check db/migrate

# See details
bundle exec queryguard analyze db/migrate
```

If it works locally, it will work in GitHub Actions.

---

## Next Steps

### 1. Require the Check for PR Merges

In your GitHub repository settings:
1. Go **Settings → Branches → Branch protection rules**
2. Add rule for `main` branch
3. Check: "Require status checks to pass before merging"
4. Select: `check-migrations` (or your job name)
5. Save

Now PRs cannot merge until migrations pass the check. ✅

### 2. Get Notified on Failure

In your GitHub repository settings:
1. Go **Settings → Notifications**
2. Enable: "Send notifications on push"
3. Choose your preference (email, Slack, etc.)

### 3. Add to Team Onboarding

Once the check is working:
- Add to **CONTRIBUTING.md**: "All migrations are checked for safety. See workflows for details."
- Link to this guide
- Share with your team

---

## Complete Examples

### Example 1: Basic Check (Recommended)

```yaml
name: QueryGuard

on:
  pull_request:
    paths: ['db/migrate/**']

jobs:
  check:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:14-alpine
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432
    
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version
          bundler-cache: true
      
      - run: bundle exec queryguard check db/migrate
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/test_db
```

### Example 2: Strict Check (Main Branch)

```yaml
name: QueryGuard - Strict

on:
  push:
    branches: [main]
    paths: ['db/migrate/**']

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version
          bundler-cache: true
      
      - run: bundle exec queryguard check db/migrate --threshold warn
```

### Example 3: Minimal (No Database)

```yaml
name: QueryGuard - Quick

on:
  pull_request:
    paths: ['db/migrate/**']

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version
          bundler-cache: true
      
      - run: bundle exec queryguard check db/migrate
```

---

## Performance

### Database Check (with PostgreSQL)
- Setup: 20-30 seconds
- Check: 5-30 seconds
- **Total**: ~40 seconds
- **Accuracy**: High (table size aware)

### Fast Check (without database)
- Setup: 20 seconds
- Check: 1-5 seconds
- **Total**: ~25 seconds
- **Accuracy**: Good (pattern matching only)

**Recommendation**: Use database check for main branch, fast check for feature branches if you want faster feedback.

---

## What Gets Checked

QueryGuard detects these risky patterns:

**CRITICAL** ❌ (Blocks with `--threshold critical | error | warn | info`)
- Unused indexes
- N+1 query patterns

**ERROR** ❌ (Blocks with `--threshold error | warn | info`)
- `remove_column` (data loss risk)
- `change_column` (risky changes)
- NOT NULL without default
- Full-table updates

**WARN** ⚠️ (Blocks with `--threshold warn | info`)
- Column renames
- SELECT *
- Missing indexes

**INFO** ℹ️ (Blocks with `--threshold info` only)
- Informational findings

---

## Real-World Setup

Here's how it looks in a real Rails project:

```
my-rails-app/
├── .github/
│   └── workflows/
│       └── queryguard.yml     ← This file (you created it)
├── db/
│   ├── migrate/
│   │   ├── 20240101000001_create_users.rb
│   │   ├── 20240102000002_add_email_to_users.rb
│   │   └── ...
│   └── schema.rb
├── Gemfile                    ← Add gem 'query_guard' here
├── Gemfile.lock               ← Auto-generated
└── .ruby-version              ← Used by workflow
```

When you:
1. Create a migration
2. Commit and push
3. Create a PR

The workflow automatically:
1. Checks out your code
2. Installs gems
3. Starts PostgreSQL
4. Runs `queryguard check`
5. Shows ✅ or ❌ on the PR

---

## Support

### Need Help?

1. **See what failed**: Click "Details" on the failed workflow
2. **Reproduce locally**: Run `bundle exec queryguard analyze db/migrate`
3. **Check the docs**: See [CI_CHECK_QUICK_REFERENCE.md](../CI_CHECK_QUICK_REFERENCE.md)
4. **Ask for help**: Open an issue with workflow output

### Common Patterns

- **Strict checks for main, loose for feature branches**: See Example 2 above
- **Multiple workflows**: See [CI_CHECK_INTEGRATION_WORKFLOWS.md](../CI_CHECK_INTEGRATION_WORKFLOWS.md)
- **Gradual rollout**: Run in report-only mode first with `|| true`

---

## FAQ

**Q: Does this slow down my CI?**  
A: No, adds ~40 seconds (mostly PostgreSQL setup). Detects issues that would cost hours to fix later.

**Q: Can I disable it temporarily?**  
A: Yes, comment out the entire `.github/workflows/queryguard.yml` file or delete it.

**Q: What if I have an old risky migration?**  
A: See [CI_CHECK_GUIDE.md](../CI_CHECK_GUIDE.md#handling-legacy-migrations) for handling legacy patterns.

**Q: Can I override/skip the check?**  
A: Only with explicit approval (not recommended). Override requires DBA review.

**Q: Which database version do I need?**  
A: The workflow uses PostgreSQL 14 (industry standard). Your local version doesn't matter.

---

## Next: Team Rollout

Once this is working:

1. **Test it** (create a test PR with a risky migration)
2. **Document it** (add to your CONTRIBUTING.md)
3. **Enable branch protection** (require check to pass before merge)
4. **Train your team** (5 minute walkthrough)

Done! Your database is now safer. 🚀

---

Need more details? See the full QueryGuard documentation:
- [CI_CHECK_GUIDE.md](../CI_CHECK_GUIDE.md) - Detailed reference
- [CI_CHECK_QUICK_REFERENCE.md](../CI_CHECK_QUICK_REFERENCE.md) - Quick commands
- [CI_CHECK_DEPLOYMENT_CHECKLIST.md](../CI_CHECK_DEPLOYMENT_CHECKLIST.md) - Team rollout
