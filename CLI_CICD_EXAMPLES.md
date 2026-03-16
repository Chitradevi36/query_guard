# QueryGuard CLI - CI/CD Integration Examples

Reference configurations for integrating QueryGuard CLI into common CI/CD systems.

## GitHub Actions

### Basic Migration Check

```yaml
name: Migration Safety Check

on:
  pull_request:
    paths:
      - db/migrate/**
  push:
    branches:
      - main

jobs:
  check-migrations:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0
      
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.1'
          bundler-cache: true
      
      - name: Check migration safety
        run: bundle exec queryguard check db/migrate --threshold error
```

### Advanced with Database

```yaml
name: Migration Safety with Database Check

on:
  pull_request:
    paths:
      - db/migrate/**

jobs:
  check-migrations:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_DB: test_db
          POSTGRES_PASSWORD: test_pass
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
          ruby-version: '3.1'
          bundler-cache: true
      
      - name: Setup database
        env:
          DATABASE_URL: postgres://postgres:test_pass@localhost/test_db
        run: bundle exec rake db:create db:migrate
      
      - name: Check migration safety (with table analysis)
        env:
          DATABASE_URL: postgres://postgres:test_pass@localhost/test_db
        run: bundle exec queryguard check db/migrate --threshold error
```

### With Artifact Upload

```yaml
name: Migration Analysis Report

on:
  pull_request:

jobs:
  analyze:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.1'
          bundler-cache: true
      
      - name: Generate analysis report
        run: bundle exec queryguard analyze --json > migration-report.json
      
      - name: Upload report
        uses: actions/upload-artifact@v3
        with:
          name: migration-report
          path: migration-report.json
      
      - name: Check safety
        run: bundle exec queryguard check db/migrate --threshold error
      
      - name: Comment on PR
        if: failure()
        uses: actions/github-script@v6
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '⚠️ Migration safety check failed. Review report in artifacts.'
            })
```

## GitLab CI

### Basic Pipeline

```yaml
stages:
  - check

migration_safety:
  stage: check
  image: ruby:3.1
  
  before_script:
    - bundle install --quiet
  
  script:
    - bundle exec queryguard check db/migrate --threshold error
  
  only:
    changes:
      - db/migrate/**
      - Gemfile.lock
```

### With Services

```yaml
migration_analysis:
  stage: check
  image: ruby:3.1
  
  services:
    - postgres:15
  
  variables:
    POSTGRES_DB: test_db
    POSTGRES_PASSWORD: test_pass
    DATABASE_URL: postgres://postgres:test_pass@postgres/test_db
  
  before_script:
    - bundle install --quiet
    - bundle exec rake db:create db:migrate
  
  script:
    - bundle exec queryguard analyze --json --verbose
    - bundle exec queryguard check db/migrate --threshold error
```

## CircleCI

### Basic Configuration

```yaml
version: 2.1

jobs:
  check-migrations:
    docker:
      - image: cimg/ruby:3.1
    
    steps:
      - checkout
      
      - run:
          name: Install dependencies
          command: bundle install
      
      - run:
          name: Check migration safety
          command: bundle exec queryguard check db/migrate --threshold error

workflows:
  test_and_check:
    jobs:
      - check-migrations
```

### With PostgreSQL

```yaml
version: 2.1

jobs:
  check-migrations:
    docker:
      - image: cimg/ruby:3.1
      - image: cimg/postgres:15
        environment:
          POSTGRES_DB: test_db
          POSTGRES_PASSWORD: test_pass
    
    environment:
      DATABASE_URL: postgresql://postgres:test_pass@localhost/test_db
    
    steps:
      - checkout
      
      - run:
          name: Wait for database
          command: dockerize -wait tcp://localhost:5432 -timeout 1m
      
      - run:
          name: Install dependencies
          command: bundle install
      
      - run:
          name: Setup database
          command: bundle exec rake db:migrate
      
      - run:
          name: Analyze migrations
          command: bundle exec queryguard analyze --json > report.json
      
      - run:
          name: Check safety
          command: bundle exec queryguard check db/migrate --threshold error
      
      - store_artifacts:
          path: report.json
```

## Travis CI

```yaml
language: ruby
ruby:
  - 3.1

services:
  - postgresql

addons:
  postgresql: '15'

env:
  - DATABASE_URL=postgresql://localhost/test_db

before_script:
  - bundle install

script:
  - bundle exec rake db:migrate
  - bundle exec queryguard check db/migrate --threshold error

notifications:
  email:
    on_failure: always
```

## Jenkins

### Basic Job

```groovy
pipeline {
  agent any
  
  stages {
    stage('Setup') {
      steps {
        sh 'ruby --version'
        sh 'bundle install'
      }
    }
    
    stage('Check Migrations') {
      steps {
        sh 'bundle exec queryguard check db/migrate --threshold error'
      }
    }
    
    stage('Generate Report') {
      steps {
        sh 'bundle exec queryguard analyze --json > report.json'
      }
    }
  }
  
  post {
    always {
      archiveArtifacts artifacts: 'report.json', allowEmptyArchive: true
    }
    
    failure {
      mail to: 'team@example.com',
           subject: "Migration check failed: ${env.BUILD_URL}",
           body: "Check migration safety: ${env.BUILD_URL}"
    }
  }
}
```

## GitLab CI with Artifacts

```yaml
migration_report:
  stage: check
  image: ruby:3.1
  
  script:
    - bundle install --quiet
    - bundle exec queryguard analyze --json --verbose > migration-report.json
    - bundle exec queryguard check db/migrate --threshold error
  
  artifacts:
    reports:
      dotenv: migration-report.json
    paths:
      - migration-report.json
    expire_in: 30 days
  
  only:
    - merge_requests
```

## Deployment Script

### Bash Script with Slack Notification

```bash
#!/bin/bash
set -e

SLACK_WEBHOOK="${SLACK_WEBHOOK:?Slack webhook URL required}"
THRESHOLD="${1:-error}"

echo "Checking migration safety (threshold: $THRESHOLD)..."

# Run check
if bundle exec queryguard check db/migrate --threshold "$THRESHOLD"; then
  STATUS="✅ Passed"
  COLOR="good"
  DEPLOY_SAFE=true
else
  STATUS="❌ Failed"
  COLOR="danger"
  DEPLOY_SAFE=false
fi

# Send to Slack
curl -X POST "$SLACK_WEBHOOK" \
  -H 'Content-type: application/json' \
  -d "{
    \"text\": \"Migration Safety Check: $STATUS\",
    \"attachments\": [{
      \"color\": \"$COLOR\",
      \"title\": \"QueryGuard Migration Check\",
      \"text\": \"Threshold: $THRESHOLD\n$(date)\",
      \"footer\": \"QueryGuard CLI\"
    }]
  }"

if [ "$DEPLOY_SAFE" = true ]; then
  echo "✅ Migrations cleared - safe to deploy!"
  exit 0
else
  echo "❌ Migration risks detected - deployment blocked"
  exit 1
fi
```

### Ruby Script with Detailed Report

```ruby
#!/usr/bin/env ruby

require 'json'
require 'net/http'

# Configuration
THRESHOLD = ENV['MIGRATION_THRESHOLD'] || 'error'
WEBHOOK_URL = ENV['SLACK_WEBHOOK']
PROJECT_ID = ENV['PROJECT_ID']

# Run analysis
report_json = `bundle exec queryguard analyze --json 2>&1`
report = JSON.parse(report_json)

# Run check
check_exit = system("bundle exec queryguard check db/migrate --threshold #{THRESHOLD}")

# Prepare message
status = check_exit ? '✅ PASSED' : '❌ FAILED'
findings_count = report['count']
by_severity = report['by_severity']

message = {
  text: "Migration Safety Check: #{status}",
  attachments: [{
    color: check_exit ? 'good' : 'danger',
    title: "QueryGuard Analysis",
    fields: [
      { title: 'Threshold', value: THRESHOLD, short: true },
      { title: 'Total Findings', value: findings_count, short: true },
      { title: 'Critical', value: by_severity['critical'] || 0, short: true },
      { title: 'Error', value: by_severity['error'] || 0, short: true },
      { title: 'Warn', value: by_severity['warn'] || 0, short: true },
      { title: 'Info', value: by_severity['info'] || 0, short: true }
    ],
    footer: 'QueryGuard CLI'
  }]
}

# Send notification
if WEBHOOK_URL
  uri = URI(WEBHOOK_URL)
  Net::HTTP.post_form(uri, { 'payload' => message.to_json })
end

exit check_exit ? 0 : 1
```

## SaaS Integration (Future)

```bash
# Upload analysis to QueryGuard SaaS portal
queryguard analyze --json \
  | curl -X POST https://app.queryguard.dev/api/analyze \
    -H "Authorization: Bearer $QUERYGUARD_API_KEY" \
    -H "Content-Type: application/json" \
    -d @-
```

## Best Practices

### Threshold Selection

- **CI/CD**: Use `--threshold error` (catches risky migrations, allows minor warnings)
- **Pre-merge**: Use `--threshold warn` (comprehensive check, requires resolving all issues)
- **Pre-production**: Use `--threshold critical` (only blocks absolute showstoppers)

### Artifact Storage

```yaml
# Store analysis reports for compliance/audit
- run: bundle exec queryguard analyze --json > migration-report.json
- store report for audit trail
```

### Failure Handling

```bash
# Fail CI build on unsafe migrations
bundle exec queryguard check db/migrate --threshold error

# Or use exit code explicitly
bundle exec queryguard check db/migrate --threshold error
if [ $? -ne 0 ]; then
  echo "Migration safety check failed"
  exit 1
fi
```

## Testing the Integration

```bash
# Local testing before committing to CI
bundle exec queryguard check db/migrate

# Dry-run of CI command
bundle exec queryguard analyze db/migrate --verbose
```

---

**Questions?** See CLI_GUIDE.md for complete command reference.
