# Running the QueryGuard Demo on Windows

This guide helps Windows developers run the QueryGuard demo without Bash.

## Prerequisites

- Ruby 3.3.0+
- A database (PostgreSQL OR SQLite)
- Git Bash or WSL (optional, for run_demo.sh)

## Database Setup

### Option 1: PostgreSQL (Recommended)

```powershell
# 1. Install PostgreSQL if needed
# Download from: https://www.postgresql.org/download/windows/

# 2. Start PostgreSQL service
# (Usually auto-starts after installation)

# 3. Create demo database
psql -U postgres -c "CREATE DATABASE queryguard_demo;"

# 4. Set environment variable
$env:DATABASE_URL="postgres://postgres:password@localhost:5432/queryguard_demo"
```

### Option 2: SQLite (Simplest)

```powershell
# No setup needed - SQLite uses local file
$env:DATABASE_URL="sqlite3:db/demo.sqlite3"
```

## Running the Demo

### Step 1: Navigate to Demo

```powershell
cd query_guard/demo
```

### Step 2: Install Dependencies

```powershell
bundle install
```

### Step 3: Analyze Migrations

```powershell
bundle exec queryguard analyze db/migrate
```

You should see:
```
✓ analyzed 6 migrations
✓ analyzed 125 queries
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔴 CRITICAL: 1 finding
🟡 WARN:     3 findings
🟢 INFO:     2 findings
```

## Additional Commands

### Get Verbose Output

```powershell
bundle exec queryguard analyze db/migrate --verbose
```

### Get JSON Output

```powershell
bundle exec queryguard analyze db/migrate --format json
```

### Check with Threshold

```powershell
# Should fail (has critical findings)
bundle exec queryguard check db/migrate --threshold critical
Write-Output $LASTEXITCODE  # Should print: 1

# Should fail (has warnings)  
bundle exec queryguard check db/migrate --threshold warn
Write-Output $LASTEXITCODE  # Should print: 1

# Should pass (info level)
bundle exec queryguard check db/migrate --threshold info
Write-Output $LASTEXITCODE  # Should print: 0
```

### Pretty-Print JSON

```powershell
# Install jq if you don't have it
# Download from: https://stedolan.github.io/jq/download/

bundle exec queryguard analyze db/migrate --format json | jq .

# Or just save to file and view
bundle exec queryguard analyze db/migrate --format json | Out-File -Path analysis.json
notepad analysis.json
```

## Troubleshooting

### "Database not found"

```powershell
# Set the correct DATABASE_URL
$env:DATABASE_URL="postgres://postgres:YOUR_PASSWORD@localhost:5432/queryguard_demo"

# Or create the database first:
psql -U postgres -c "CREATE DATABASE queryguard_demo;"
```

### "bundle: command not found"

```powershell
# Make sure you're in the demo directory
cd query_guard/demo

# And bundler is installed
gem install bundler
bundle install
```

### "PostgreSQL not available"

```powershell
# Use SQLite instead
$env:DATABASE_URL="sqlite3:db/demo.sqlite3"
bundle install
bundle exec queryguard analyze db/migrate
```

### "queryguard command not found"

```powershell
# Make sure you're in demo directory and bundler installed
cd query_guard/demo
bundle install

# Then run with bundle exec
bundle exec queryguard analyze db/migrate
```

## Demo Files

What each file demonstrates:

```
Migrations:
├── 01_create_users ........... ✅ Clean migration (INFO)
├── 02_add_posts_table ........ 🟡 Missing index (WARN)
├── 03_add_index_on_posts_content 🟡 No CONCURRENTLY (WARN)
├── 04_remove_phone_from_users . 🔴 Data loss (CRITICAL)
├── 05_add_comments_table ..... ✅ Clean migration (INFO)
└── 06_add_status_to_users ... 🟡 NOT NULL without default (WARN)

Models:
├── user.rb ................... SELECT *, N+1 examples
└── post.rb ................... Unbounded queries, +1 examples
```

## Expected Results

When you run the demo, you should see:

✅ **Summary**: 1 CRITICAL, 3 WARN, 2 INFO  
✅ **Time**: <500ms for analysis  
✅ **JSON**: Valid, well-structured JSON output  
✅ **Recommendations**: Each finding has actionable fixes  

If you see these results, the demo is working correctly!

## For Videos & Screenshots

### Quick Demo (60 seconds)

```powershell
cd query_guard/demo
bundle install
bundle exec queryguard analyze db/migrate
# Point out critical findings
```

### Detailed Demo (5 minutes)

```powershell
cd query_guard/demo
bundle install
bundle exec queryguard analyze db/migrate --verbose
# Show recommendations section
```

### JSON Demo

```powershell
cd query_guard/demo
bundle exec queryguard analyze db/migrate --format json | Out-File analysis.json
# Open in VS Code to show structure
code analysis.json
```

## Notes

- The demo doesn't require an actual PostgreSQL connection set up
- It just needs the migrations directory analyzed
- Database is optional (only needed for certain advanced detections)
- All 6 migrations are intentionally problematic (except 01 and 05)
- This validates QueryGuard's detection capabilities

## Next Steps

After running the demo:

1. **Review findings** in README.md
2. **Understand patterns** in QUICK_REF.md  
3. **Customize demo** by adding new migrations to db/migrate/
4. **Extend detection** by modifying QueryGuard and re-running

See demo/README.md for full documentation.

---

*QueryGuard Demo Guide for Windows | March 16, 2026*
