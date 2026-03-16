# Rails + GitHub Actions: Get QueryGuard Working in 5 Minutes

Complete, copy-paste ready guide for Rails teams.

**Time**: 5 minutes  
**Prerequisites**: Rails project with Git and GitHub  
**Result**: Automated migration safety checks on every PR ✅

---

## Step 1: Add the Gem (1 min)

Edit your `Gemfile`:

```ruby
group :development, :test do
  gem 'query_guard'
end
```

Run:
```bash
bundle install
```

Commit:
```bash
git add Gemfile Gemfile.lock
git commit -m "Add queryguard gem"
```

---

## Step 2: Create the Workflow (1 min)

Create this file: `.github/workflows/queryguard.yml`

Copy-paste the content below:

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
      
      - name: Analyze migrations
        run: bundle exec queryguard analyze db/migrate
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/test_db
      
      - name: Check migration safety
        run: bundle exec queryguard check db/migrate
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/test_db
```

---

## Step 3: Commit the Workflow (1 min)

```bash
git add .github/workflows/queryguard.yml
git commit -m "Add QueryGuard GitHub Actions workflow"
git push origin main
```

---

## Step 4: Test It (2 min)

Create a test PR with a new migration:

```bash
git checkout -b test/migration-safety
```

Create a migration file in `db/migrate/`:

```ruby
# db/migrate/20240316000001_add_email_to_users.rb
class AddEmailToUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :users, :email, :string
  end
end
```

Push and create a PR:
```bash
git add db/migrate/
git commit -m "Add email column to users"
git push origin test/migration-safety
```

Open a PR on GitHub. **The workflow runs automatically!** ✅

---

## What Happens

### When Migration Is Safe ✅
- Workflow shows a green checkmark
- PR shows "All checks passed"
- You can merge immediately

### When Migration Is Risky ❌
- Workflow shows a red X
- PR shows "Some checks failed"
- Click "Details" to see what's wrong
- Fix the migration and push again (workflow runs again automatically)

---

## Example Risky Migrations

Here are patterns that would cause the check to fail:

### ❌ Removing a column (data loss)
```ruby
def change
  remove_column :users, :email
end
```

### ❌ Changing column type (potential data loss)
```ruby
def change
  change_column :users, :email, :integer
end
```

### ❌ Adding NOT NULL without default
```ruby
def change
  add_column :users, :status, :string, null: false
  # What about existing rows?
end
```

### ✅ Safe alternatives

```ruby
# Adding a column with a default
def change
  add_column :users, :email, :string, default: ""
end

# Removing a column (safer if you need to)
def change
  reversible do |dir|
    dir.up { remove_column :users, :email }
    dir.down { add_column :users, :email, :string }
  end
end
```

---

## Common Questions

### Do I need PostgreSQL running locally?

No. The workflow spins up PostgreSQL automatically. Your local setup doesn't matter.

### How long does the check take?

About 40 seconds per PR (30s setup, 10s check). This is fast.

### Can I make the check stricter?

Yes! Edit the workflow file and change:

```yaml
run: bundle exec queryguard check db/migrate --threshold warn
```

Options:
- `critical` = Only critical findings block (permissive)
- `error` = Critical + Error block (default)
- `warn` = Critical + Error + Warning block (strict)

### Can I skip the check for a specific commit?

Not recommended, but yes. Use `[skip migrations]` in your commit message (requires setup).

Better: Fix the migration to be safe.

### What if the check is wrong?

Open an issue with the migration code. QueryGuard should be correct 99% of the time.

### Can I test locally first?

Yes!

```bash
bundle exec queryguard check db/migrate
```

Exit codes:
- `0` = Safe
- `1` = Risky
- `2` = Error

---

## Next Steps

### For Individual Developers
1. Run `bundle exec queryguard check db/migrate` before pushing
2. Read output to understand risky patterns
3. Use [Query Guard Quick Reference](../CI_CHECK_QUICK_REFERENCE.md) for help

### For Team Leaders
1. Require the check for main branch (Settings → Branches → Protection)
2. Share this guide with team members
3. Set up Slack notifications (optional)
4. Review patterns found in first week to tune threshold

### For DevOps/SRE
1. Monitor workflow pass/fail rate
2. Check execution time trends
3. Add to your deployment pipeline if needed
4. See [GitHub Actions Setup Guide](../docs/GITHUB_ACTIONS_SETUP.md) for advanced options

---

## Customization (Optional)

### Different Rules for Different Branches

**Strict check on main:**

Create `.github/workflows/queryguard-main.yml`:

```yaml
name: Strict Check on Main

on:
  push:
    branches: [main]
    paths: ['db/migrate/**']

jobs:
  strict-check:
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
      - run: bundle exec queryguard check db/migrate --threshold warn
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/test_db
```

### Faster Check (No Database)

Skip PostgreSQL setup for speed:

```yaml
- name: Check migration safety
  run: bundle exec queryguard check db/migrate
  # Remove the DATABASE_URL env var
```

Trade-off: Less accurate (doesn't see table sizes), but 10x faster.

### Detailed Output

Add `--verbose`:

```yaml
- run: bundle exec queryguard analyze db/migrate --verbose
```

---

## Troubleshooting

### Workflow doesn't run
- Check: Is `.github/workflows/queryguard.yml` committed?
- Check: Go to "Actions" tab in GitHub - do you see the workflow?
- Check: Does your commit touch `db/migrate/`?

### "queryguard command not found"
- Verify: `Gemfile` has `gem 'query_guard'`
- Verify: `Gemfile.lock` is committed
- Fix: Delete `.github/workflows/queryguard.yml`, re-add it, commit `Gemfile.lock`

### "Database connection refused"
- This usually means PostgreSQL didn't start
- Add delay before check:
  ```yaml
  - run: sleep 5
  - run: bundle exec queryguard check db/migrate
  ```

### "Ruby version not found"
- Create `.ruby-version` file:
  ```bash
  echo "3.1.0" > .ruby-version
  git add .ruby-version
  ```
  (Use your actual Ruby version)

---

## Reference

Full documentation available:
- **[GitHub Actions Setup Guide](../docs/GITHUB_ACTIONS_SETUP.md)** - Complete reference
- **[Workflow Examples](../examples/workflows/)** - More patterns
- **[CI Check Quick Reference](../CI_CHECK_QUICK_REFERENCE.md)** - Commands
- **[Main README](../README.md)** - Overview

---

## Success! 🎉

You've just set up automated database migration safety checks for your team.

**What's happening now:**
- ✅ Every PR touching migrations gets checked automatically
- ✅ Risky patterns are caught before they reach production
- ✅ Your team can fix issues before merging
- ✅ Database safety improves over time

**Time saved:** This setup prevents hours of debugging production database issues.

**Next:** Create a real PR and watch it work! 🚀

---

**Questions?** Check the troubleshooting section above or see the full [GitHub Actions Setup Guide](../docs/GITHUB_ACTIONS_SETUP.md).
