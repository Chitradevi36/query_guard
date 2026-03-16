# CI Check Integration - Rails Developer Workflows

This guide shows how to integrate `queryguard check` into real Rails development workflows.

## 1. Pre-Commit Hook (Local Development)

**File**: `.git/hooks/pre-commit`

```bash
#!/bin/bash
# Prevent committing risky migrations

MIGRATIONS=$(git diff --cached --name-only | grep "^db/migrate/.*\.rb$")

if [ -z "$MIGRATIONS" ]; then
  exit 0  # No migrations to check
fi

# Check before allowing commit
bundle exec queryguard check db/migrate --threshold error

if [ $? -eq 0 ]; then
  echo "✅ Migrations approved - commit allowed"
  exit 0
else
  echo "❌ Risky migrations detected - commit blocked"
  echo "Review with: bundle exec queryguard analyze db/migrate --json"
  exit 1
fi
```

**Setup**:
```bash
chmod +x .git/hooks/pre-commit
# Now every commit will check migrations first
```

## 2. GitHub Actions Workflow

**File**: `.github/workflows/database-check.yml`

```yaml
name: Database Migration Check

on:
  pull_request:
    paths:
      - 'db/migrate/**'
  push:
    branches: [main, develop]
    paths:
      - 'db/migrate/**'

jobs:
  check-migrations:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:14
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
      - uses: actions/checkout@v3
      
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.1
          bundler-cache: true
      
      - name: Check migration safety
        run: |
          bundle exec queryguard check db/migrate --threshold error
      
      - name: Get details on failure
        if: failure()
        run: |
          echo "## Migration Analysis Results" >> $GITHUB_STEP_SUMMARY
          bundle exec queryguard analyze db/migrate --verbose >> $GITHUB_STEP_SUMMARY
      
      - name: Export findings for review
        if: failure()
        run: |
          bundle exec queryguard analyze db/migrate --json > findings.json
      
      - name: Comment on PR
        if: failure()
        uses: actions/github-script@v6
        with:
          script: |
            const findings = require('./findings.json');
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `### ⚠️ Database Migration Review Required\n\nFound ${findings.findings.length} issues in migrations:\n\n${findings.findings.map(f => `- **${f.severity}**: ${f.description}`).join('\n')}`
            });
```

## 3. GitLab CI Pipeline

**File**: `.gitlab-ci.yml`

```yaml
stages:
  - check
  - test
  - deploy

check_migrations:
  stage: check
  image: ruby:3.1
  script:
    - bundle install
    - bundle exec queryguard check db/migrate --threshold error
  only:
    - merge_requests
    - develop
    - main

check_strict_on_main:
  stage: check
  image: ruby:3.1
  script:
    - bundle install
    # Stricter check for production branch
    - bundle exec queryguard check db/migrate --threshold warn
  only:
    - main
  allow_failure: false

test_suite:
  stage: test
  image: ruby:3.1
  script:
    - bundle install
    - bundle exec rspec
  dependencies:
    - check_migrations
```

## 4. Jenkins Pipeline

**File**: `Jenkinsfile`

```groovy
pipeline {
  agent any
  
  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }
    
    stage('Check Migrations') {
      steps {
        sh '''
          bundle install
          bundle exec queryguard check db/migrate --threshold error
        '''
      }
      post {
        failure {
          sh 'bundle exec queryguard analyze db/migrate --json > migration-findings.json'
          publishHTML([
            reportDir: '.',
            reportFiles: 'migration-findings.json',
            reportName: 'Migration Findings'
          ])
        }
      }
    }
    
    stage('Run Tests') {
      steps {
        sh 'bundle exec rspec'
      }
    }
    
    stage('Deploy') {
      when {
        branch 'main'
      }
      steps {
        // Check again before deploying to main
        sh 'bundle exec queryguard check db/migrate --threshold warn'
        sh 'bundle exec rails db:migrate:status'
        sh 'bundle exec cap production deploy'
      }
    }
  }
  
  post {
    always {
      cleanWs()
    }
  }
}
```

## 5. Makefile Task (Development)

**File**: `Makefile`

```makefile
.PHONY: check-migrations check-migrations-strict analyze-migrations

# Standard check (blocks on error/critical)
check-migrations:
	@echo "Checking migrations (threshold: error)..."
	bundle exec queryguard check db/migrate --threshold error

# Strict check (blocks on warn and above)
check-migrations-strict:
	@echo "Checking migrations (threshold: warn)..."
	bundle exec queryguard check db/migrate --threshold warn

# Analyze migrations with full details
analyze-migrations:
	@echo "Analyzing migrations..."
	bundle exec queryguard analyze db/migrate --verbose

# Check before deploying to production
check-before-prod:
	@echo "Pre-production migration check..."
	bundle exec queryguard check db/migrate --threshold warn
	@echo "✅ Safe to deploy to production"

# Check before committing
check-before-commit:
	@echo "Pre-commit migration check..."
	bundle exec queryguard check db/migrate --threshold error
	@if [ $$? -eq 0 ]; then echo "✅ Ready to commit"; else echo "❌ Fix migrations first"; fi
```

**Usage**:
```bash
make check-migrations          # Quick check
make analyze-migrations        # Get details
make check-before-prod         # Stricter, production check
```

## 6. Rake Task (Rails Integration)

**File**: `lib/tasks/migrations.rake`

```ruby
namespace :migrations do
  desc "Check migration safety (gate for CI/CD)"
  task check: :environment do
    require 'query_guard'
    
    checker = QueryGuard::CLI::Commands::Check.new
    threshold = ENV['MIGRATION_THRESHOLD'] || 'error'
    
    puts "Checking migrations (threshold: #{threshold})..."
    
    exit_code = checker.execute(
      path: 'db/migrate',
      threshold: threshold,
      format: ENV['MIGRATION_FORMAT'] || 'text'
    )
    
    exit exit_code
  end
  
  desc "Analyze migrations with full output"
  task analyze: :environment do
    require 'query_guard'
    
    analyzer = QueryGuard::CLI::Commands::Analyze.new
    analyzer.execute(
      path: 'db/migrate',
      verbose: true
    )
  end
end
```

**Usage**:
```bash
rails migrations:check                    # Check with default threshold
MIGRATION_THRESHOLD=warn rails migrations:check    # Stricter check
rails migrations:analyze                  # Full analysis
```

## 7. Docker-Compose Development

**File**: `docker-compose.yml`

```yaml
version: '3.8'

services:
  web:
    build: .
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgres://postgres:password@db:5432/app_development
    volumes:
      - .:/app
    depends_on:
      - db
    command: |
      bash -c "
        bundle install
        bundle exec queryguard check db/migrate --threshold error
        bundle exec rails db:create db:migrate
        rails server -b 0.0.0.0
      "
  
  db:
    image: postgres:14
    environment:
      POSTGRES_PASSWORD: password
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

## 8. TeamCity Build Configuration

**File**: `teamcity-config.xml` (or via UI)

```xml
<buildType>
  <name>Database Migration Safety Check</name>
  <steps>
    <step>
      <type>simpleRunner</type>
      <properties>
        <entry key="script.content">
          <value>
#!/bin/bash
set -e

echo "Installing dependencies..."
bundle install

echo "Checking migration safety..."
bundle exec queryguard check db/migrate --threshold error

echo "✅ All migrations safe to deploy"
          </value>
        </entry>
      </properties>
    </step>
  </steps>
</buildType>
```

## 9. Docker Build Stage Check

**File**: `Dockerfile`

```dockerfile
FROM ruby:3.1-slim

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

# Check migrations are safe before building
RUN bundle exec queryguard check db/migrate --threshold error || \
    (echo "❌ Risky migrations detected in Dockerfile build" && exit 1)

# Continue with normal build
RUN bundle exec rails assets:precompile db:schema:load

CMD ["rails", "server", "-b", "0.0.0.0"]
```

## 10. Development Script

**File**: `bin/check-migrations`

```bash
#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

THRESHOLD=${1:-error}

echo -e "${YELLOW}Checking migrations (threshold: ${THRESHOLD})...${NC}"

bundle exec queryguard check db/migrate --threshold "$THRESHOLD"
EXIT_CODE=$?

case $EXIT_CODE in
  0)
    echo -e "${GREEN}✅ All migrations safe${NC}"
    exit 0
    ;;
  1)
    echo -e "${RED}❌ Risky migrations detected${NC}"
    echo ""
    echo "Get details:"
    echo "  bundle exec queryguard analyze db/migrate --json"
    exit 1
    ;;
  2)
    echo -e "${RED}⚠️  Error checking migrations${NC}"
    exit 2
    ;;
esac
```

**Setup and usage**:
```bash
chmod +x bin/check-migrations
bin/check-migrations              # Check with default threshold
bin/check-migrations warn         # Check with strict threshold
```

## 11. Capistrano Deployment Hook

**File**: `config/deploy.rb`

```ruby
namespace :deploy do
  desc "Check migrations before deploying"
  task :check_migrations do
    run_locally do
      execute :bundle, "exec queryguard check db/migrate --threshold warn"
    end
    
    puts "✅ Migrations checked and approved for deployment"
  end
end

before 'deploy:migrate', 'deploy:check_migrations'
```

## 12. GitHub Branch Protection Rule

Enable this check as a required status check:

1. Go to **Settings → Branches → Branch protection rules**
2. Create rule for `main` branch
3. Under "Require status checks to pass before merging", add:
   - `check-migrations` (the workflow job name)
   - Mark as **required**
4. Save

Now PRs cannot merge unless migrations pass the check.

---

## Exit Code Handling Patterns

### Bash Scripts
```bash
#!/bin/bash
set -e  # Exit on any error
bundle exec queryguard check db/migrate --threshold error
# If exit code != 0, script stops here
```

### Python CI Systems
```python
import subprocess
import sys

result = subprocess.run(
    ['bundle', 'exec', 'queryguard', 'check', 'db/migrate', '--threshold', 'error'],
    cwd='/app'
)

if result.returncode == 0:
    print("✅ Migrations approved")
    sys.exit(0)
elif result.returncode == 1:
    print("❌ Risky migrations detected")
    sys.exit(1)
else:
    print("⚠️ Error checking migrations")
    sys.exit(2)
```

### Ruby Scripts
```ruby
require 'open3'

stdout, stderr, status = Open3.capture3(
  'bundle', 'exec', 'queryguard', 'check', 'db/migrate', '--threshold', 'error'
)

case status.exitstatus
when 0
  puts "✅ Migrations approved"
when 1
  puts "❌ Risky migrations detected"
  puts stdout
  abort
when 2
  puts "⚠️ Error checking migrations"
  abort
end
```

---

## Threshold Selection Guide

**Dev/Feature Branches**:
```bash
# Allow anything except critical errors
queryguard check db/migrate --threshold error
```

**Main Branch (Merge Gate)**:
```bash
# Block warnings and above before merge
queryguard check db/migrate --threshold warn
```

**Production Deployment**:
```bash
# Most strict - must be clean before deploying
queryguard check db/migrate --threshold warn
```

**Legacy Systems (High Tolerance)**:
```bash
# Only block critical (if system is resilient)
queryguard check db/migrate --threshold critical
```

---

## Monitoring & Alerting

### Track Migration Safety Over Time

```bash
#!/bin/bash
# Save results daily
DATE=$(date +%Y-%m-%d)
bundle exec queryguard analyze db/migrate --json > migrations-${DATE}.json
echo "Migrations checked at $(date)" >> migrations.log
```

### Set Alerts

- Alert if `queryguard check` fails in main branch
- Alert if number of errors increases 50% week-over-week
- Alert if critical findings detected

---

## Best Practices

1. **Default to `error` threshold** for feature branches
2. **Use `warn` threshold** for main/production merges
3. **Check locally before pushing** (pre-commit hook)
4. **Make failure notification clear** (Slack, email, GitHub comment)
5. **Provide remediation path** (link to detailed analysis)
6. **Review trends** (weekly safety metrics)
7. **Override carefully** (document why in commit message)
8. **Test threshold in staging** before enforcing on main

---

## Common Patterns

### Pattern 1: Fail Fast
```bash
bundle exec queryguard check db/migrate --threshold error || exit 1
```
Good for: Quick feedback, development

### Pattern 2: Report & Continue
```bash
bundle exec queryguard check db/migrate --threshold error 
STATUS=$?
if [ $STATUS -eq 1 ]; then
  echo "Review findings in artifacts"
fi
exit 0  # Don't fail pipeline, let humans review
```
Good for: Learning phase, monitoring

### Pattern 3: Graduated Thresholds
```bash
# Feature branch - permissive
bundle exec queryguard check db/migrate --threshold error

# Main branch - strict
if [ "$BRANCH" = "main" ]; then
  bundle exec queryguard check db/migrate --threshold warn
fi
```
Good for: Balancing speed with safety

### Pattern 4: Manual Override
```bash
if [ "$SKIP_MIGRATION_CHECK" = "true" ]; then
  echo "⚠️  Skipping migration check (manual override)"
else
  bundle exec queryguard check db/migrate --threshold error
fi
```
Good for: Emergency hotfixes

---

This guide shows how to integrate QueryGuard into your real workflow. Pick the patterns that match your team's process and risk tolerance.
