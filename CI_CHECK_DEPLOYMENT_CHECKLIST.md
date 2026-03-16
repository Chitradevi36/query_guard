# CI Check Mode - Team Onboarding & Deployment Checklist

Use this checklist to roll out `queryguard check` to your team.

---

## Phase 1: Planning & Understanding (Day 1)

### Stakeholder Alignment
- [ ] **Development Team**: Review [CI_CHECK_QUICK_REFERENCE.md](CI_CHECK_QUICK_REFERENCE.md)
- [ ] **DevOps/SRE**: Review [CI_CHECK_GUIDE.md](CI_CHECK_GUIDE.md) - CI/CD section
- [ ] **DBA/Database Team**: Review [CI_CHECK_GUIDE.md](CI_CHECK_GUIDE.md) - Threshold selection guide
- [ ] **Release Manager**: Review this checklist and [CI_CHECK_SUMMARY.md](CI_CHECK_SUMMARY.md)

### Decision Points
- [ ] **Choose Default Threshold**
  - [ ] Feature branches: `error` (default) ← Recommended
  - [ ] Main branch: `error` or `warn` (choose one)
  - [ ] Production deployment: `warn` or `critical` (choose one)
  
  *Document your choices in team wiki*

- [ ] **Choose Failure Mode**
  - [ ] Fail hard: Block pipelines on threshold exceeded
  - [ ] Report & continue: Notify team but allow merging with acknowledgment
  - [ ] Phased rollout: Report only for first 2 weeks, then enforce
  
  *Recommend: Report only → Phased → Enforce over 4 weeks*

- [ ] **Choose CI/CD Integration Points**
  - [ ] Pre-commit hook (developer machines)
  - [ ] Pull request checks (GitHub/GitLab/etc)
  - [ ] Main branch gate (pre-merge)
  - [ ] Pre-deployment check (production)
  
  *Recommend: Start with PR checks, add pre-commit later*

### Risk Assessment
- [ ] Review existing migrations for "alert fatigue" risk
- [ ] Run `queryguard analyze db/migrate` to understand current findings
- [ ] Plan training for "what to do when check fails"
- [ ] Identify 1-2 champions who will help others

---

## Phase 2: Technical Setup (Days 2-3)

### Environment Setup

#### All Team Members
- [ ] **Ruby/Rails Environment**
  - [ ] Ruby 2.7+ installed: `ruby --version`
  - [ ] Bundler installed: `bundle --version`
  - [ ] Rails gems up to date: `bundle update`

- [ ] **QueryGuard Gem**
  - [ ] Added to `Gemfile`:
    ```ruby
    gem 'query_guard', require: false
    ```
  - [ ] Installed: `bundle install`
  - [ ] Verified: `bundle exec queryguard --version`

#### Developers (Add to Git hooks)
- [ ] **Pre-commit hook** (optional, but recommended)
  - [ ] Download/create `.git/hooks/pre-commit`
  - [ ] Make executable: `chmod +x .git/hooks/pre-commit`
  - [ ] Test: Create a test migration, run `git commit`
  - [ ] Verify: Pre-commit check runs before allowing commit

#### DevOps/SRE (Add to CI/CD)
- [ ] **GitHub Actions** (if using GitHub)
  - [ ] Create `.github/workflows/migration-check.yml`
  - [ ] Set threshold to your chosen default
  - [ ] Test by creating pull request with risky migration
  - [ ] Verify job runs and exits with correct code

- [ ] **GitLab CI** (if using GitLab)
  - [ ] Add job to `.gitlab-ci.yml`
  - [ ] Test in feature branch
  - [ ] Verify proper exit codes

- [ ] **Jenkins** (if using Jenkins)
  - [ ] Add step to deployment pipeline
  - [ ] Test with trigger
  - [ ] Add post-failure notifications

- [ ] **Other CI/CD System**
  - [ ] Follow [CI_CHECK_INTEGRATION_WORKFLOWS.md](CI_CHECK_INTEGRATION_WORKFLOWS.md) for your system
  - [ ] Test integration
  - [ ] Set up notifications

### Database Setup
- [ ] **PostgreSQL Connection** (optional, but recommended for better analysis)
  - [ ] Development DB accessible: `psql -U postgres -d myapp_development`
  - [ ] Connection works: `bundle exec queryguard analyze db/migrate` (check for DB info in output)
  - [ ] Note: QueryGuard degrades gracefully if DB unavailable

---

## Phase 3: Testing & Validation (Day 4)

### Manual Testing

#### Test 1: No Findings
```bash
cd repo
git checkout -b test/safe-migration
# Add safe migration: add_column :users, :email, :string, null: false, default: ""
git add db/migrate/
bundle exec queryguard check db/migrate --threshold error
# Expected: exit code 0, "✅ Clear"
```
- [ ] Test passed (exit code 0)

#### Test 2: Warnings Only (Below Error Threshold)
```bash
git checkout -b test/warn-migration
# Add warning migration: SELECT * style code
git add db/migrate/
bundle exec queryguard check db/migrate --threshold error
# Expected: exit code 0 (warnings don't block error threshold)
```
- [ ] Test passed (exit code 0)

#### Test 3: Error Level Finding (Should Block)
```bash
git checkout -b test/risky-migration
# Add risky migration: remove_column :users, :email
git add db/migrate/
bundle exec queryguard check db/migrate --threshold error
# Expected: exit code 1, shows finding
```
- [ ] Test passed (exit code 1)

#### Test 4: Different Thresholds
```bash
bundle exec queryguard check db/migrate --threshold critical
# Expected: Different result than error threshold
```
- [ ] Test passed

#### Test 5: JSON Output
```bash
bundle exec queryguard check db/migrate --json
# Expected: Valid JSON output
```
- [ ] Test passed (valid JSON)

### CI/CD Testing

#### GitHub Actions
- [ ] **Create test PR with risky migration**
  - [ ] Push test migration to feature branch
  - [ ] Create PR
  - [ ] Wait for workflow to run
  - [ ] Verify: Workflow shows failure (red X)
  - [ ] Note: PR should not allow merge (if protection enabled)

#### Other CI/CD Systems
- [ ] **Follow similar pattern** for your system
- [ ] Verify notifications are working
- [ ] Check that success/failure is clear

### Team Testing
- [ ] **Developer runs local check**
  - [ ] Creates test migration
  - [ ] Runs `queryguard check db/migrate`
  - [ ] Understands the output
  - [ ] Reads recommended remediation

- [ ] **Team reads guidance**
  - [ ] Opens [CI_CHECK_QUICK_REFERENCE.md](CI_CHECK_QUICK_REFERENCE.md)
  - [ ] Finds command for their scenario
  - [ ] Successfully runs it

---

## Phase 4: Documentation & Training (Day 5)

### Internal Documentation
- [ ] **Team Wiki/Confluence**
  - [ ] Copy [CI_CHECK_QUICK_REFERENCE.md](CI_CHECK_QUICK_REFERENCE.md) to internal wiki
  - [ ] Add your team's chosen thresholds
  - [ ] Add your team's DBA contact for questions
  - [ ] Add examples of "safe" vs "risky" migrations for your domain

- [ ] **Runbook**
  - [ ] "What to do when `queryguard check` fails"
  - [ ] Sample fix for each finding type (if applicable)
  - [ ] Escalation path (who to contact)
  - [ ] Emergency override procedure (if needed)

- [ ] **README or CONTRIBUTING.md**
  - [ ] Add one-liner: "Migrations are checked for safety. Run `bundle exec queryguard check db/migrate` before committing."
  - [ ] Link to full guide

### Team Training
- [ ] **15-minute walkthrough**
  - [ ] Show the four findings that trigger blocks
  - [ ] Demo: "Here's what happens when you add a risky migration"
  - [ ] Demo: "Here's how to fix it"
  - [ ] Q&A

- [ ] **Pair programming** (optional)
  - [ ] Pick 1-2 developers as "migration safety champions"
  - [ ] Have them create first safe migration together
  - [ ] Have them fix a risky migration together
  - [ ] Make them point-person for team questions

### Document Creation/Review
- [ ] **Review generated docs**
  - [ ] [CI_CHECK_SUMMARY.md](CI_CHECK_SUMMARY.md) - Overview
  - [ ] [CI_CHECK_QUICK_REFERENCE.md](CI_CHECK_QUICK_REFERENCE.md) - Daily use
  - [ ] [CI_CHECK_GUIDE.md](CI_CHECK_GUIDE.md) - Deep dive
  - [ ] [CI_CHECK_INTEGRATION_WORKFLOWS.md](CI_CHECK_INTEGRATION_WORKFLOWS.md) - Implementation examples

- [ ] **Customize for your team** (optional)
  - [ ] Add your company logo to internal docs
  - [ ] Add your DBA contact info
  - [ ] Add your threshold choices
  - [ ] Add examples using your codebase

---

## Phase 5: Gradual Rollout (Week 1-4)

### Week 1: Monitoring Mode
- [ ] **CI runs but doesn't block**
  ```bash
  # In CI config: capture results but exit 0
  bundle exec queryguard check db/migrate --threshold error || true
  ```
  
  - [ ] GitHub Actions configured to report but not fail
  - [ ] Slack notifications enabled (if available)
  - [ ] Team reviews findings without pressure
  - [ ] Identify migrations that need fixing (backlog)

- [ ] **Team creates first migration**
  - [ ] Developer goes through check flow
  - [ ] Gets feedback (if failed)
  - [ ] Fixes if needed
  - [ ] Learns the process

- [ ] **Document findings**
  - [ ] Run: `queryguard analyze db/migrate --json > baseline.json`
  - [ ] Archive baseline
  - [ ] Set this as your "starting point"

### Week 2-3: Enforcement on New Migrations
- [ ] **Enable blocking for PRs**
  ```bash
  # CI now fails on threshold exceeded
  bundle exec queryguard check db/migrate --threshold error
  ```
  
  - [ ] CI configuration updated to fail
  - [ ] Team notified: "Checks now enforce"
  - [ ] New migrations must pass
  - [ ] Existing at-risk migrations allowed (legacy)
  - [ ] Documentation accessible and linked in PR comments

- [ ] **Enforce for small group first**
  - [ ] Enable for 1 team's PRs
  - [ ] Gather feedback
  - [ ] Make adjustments if needed
  - [ ] Expand to all teams

- [ ] **Create escalation procedure**
  - [ ] Document: "What if I need to override?"
  - [ ] Example: DBA approval required
  - [ ] Update runbook with process

### Week 4: Full Enforcement
- [ ] **Enable for all repositories/branches**
  - [ ] Main branch protection enabled
  - [ ] All developers required to pass check
  - [ ] No exceptions without documented approval

- [ ] **Monitor metrics**
  - [ ] Track weekly failed checks
  - [ ] Identify patterns in failures
  - [ ] Share trends with team

- [ ] **Collect feedback**
  - [ ] Survey: "Was check helpful?"
  - [ ] Survey: "Did threshold feel right?"
  - [ ] Adjust if needed for Week 5+

---

## Phase 6: Long-Term Maintenance (Ongoing)

### Weekly
- [ ] **Review findings** (if new risky migrations detected)
- [ ] **Check exit codes** (ensure CI integration working)
- [ ] **Answer team questions** (Slack, standup, etc)

### Monthly
- [ ] **Trend analysis**
  - [ ] How many migrations are blocked monthly?
  - [ ] Are developers writing safer migrations?
  - [ ] Any patterns in failures?

- [ ] **Threshold review**
  - [ ] Is current threshold still appropriate?
  - [ ] Should main branch threshold be stricter/looser?
  - [ ] Should warning threshold change?

- [ ] **Documentation update**
  - [ ] Add new examples to runbook
  - [ ] Clarify confusing guidance
  - [ ] Update DBA contact if changed

### Quarterly
- [ ] **Safety metrics review**
  - [ ] Before/after: Risk migration count
  - [ ] Before/after: Production incidents related to migrations
  - [ ] ROI: Time saved by early detection vs time spent fixing

- [ ] **Tool update check**
  - [ ] Is QueryGuard version current?
  - [ ] Any new features to use?
  - [ ] Any bug fixes to apply?

---

## Rollback Plan (If Needed)

If you need to disable the check temporarily:

### Disable CI Check
```yaml
# In your CI config, comment out:
# - run: bundle exec queryguard check db/migrate

# Or set:
- run: bundle exec queryguard check db/migrate || true
```

### Disable Pre-commit Hook
```bash
# Temporarily disable:
chmod -x .git/hooks/pre-commit

# Re-enable later:
chmod +x .git/hooks/pre-commit
```

### Steps to Rollback
1. [ ] Notify team (Slack, email)
2. [ ] Update CI config to not enforce
3. [ ] Update internal documentation
4. [ ] Document reason in ticket/incident report
5. [ ] Schedule re-enablement date
6. [ ] Post-mortem: Why did we need to disable?

---

## Success Criteria

### Week 1 Goals
- [ ] All developers understand how to run check
- [ ] Pre-commit hook (if chosen) working for 50%+ of team
- [ ] Zero blockers/escalations

### Week 2-3 Goals
- [ ] CI integration working without false positives
- [ ] All new migrations passing check
- [ ] Team confidence increasing (fewer questions)

### Month 1 Goal
- [ ] Zero risky migrations merged to main branch
- [ ] Team can fix "failed check" in < 10 minutes
- [ ] Runbook answers 90% of team questions

### Ongoing Goals
- [ ] Deployment safety metrics improving
- [ ] Zero migration-related production incidents
- [ ] Team finds value in the check (positive feedback)

---

## Support & Escalation

### Tier 1: Self-Service (Docs)
- [CI_CHECK_QUICK_REFERENCE.md](CI_CHECK_QUICK_REFERENCE.md) - Common scenarios
- [CI_CHECK_GUIDE.md](CI_CHECK_GUIDE.md) - Detailed guidance
- `bundle exec queryguard check --help` - Built-in help

### Tier 2: Team Resources
- **Migration Safety Champion**: [Name] - Can help fix failed checks
- **DBA Review**: [Contact] - For threshold overrides
- **DevOps Support**: [Contact] - For CI/CD integration issues

### Tier 3: Escalation
- **Unable to pass after 1 hour**: Escalate to DBA/Architect
- **CI integration broken**: Escalate to DevOps
- **Tool not working correctly**: Check GitHub issues or contact maintainer

---

## Quick Reference: Common Commands

```bash
# Check if your migrations are safe (before committing)
bundle exec queryguard check db/migrate --threshold error

# See detailed analysis (if check fails)
bundle exec queryguard analyze db/migrate --verbose

# Get JSON for automation
bundle exec queryguard check db/migrate --json

# Override threshold for stricter check (e.g., main branch)
bundle exec queryguard check db/migrate --threshold warn

# Force display of all findings (even below threshold)
bundle exec queryguard analyze db/migrate --json | jq '.findings'
```

---

## Sign-Off

- [ ] **Development Lead**: Reviewed and approved
- [ ] **DevOps Engineer**: CI/CD integration tested
- [ ] **Database Administrator**: Threshold choices reviewed
- [ ] **Project Manager**: Timeline and risks understood

---

**Date Deployed**: ________________  
**Team**: ________________  
**Lead Contact**: ________________  

For questions or updates, refer to the support tier above.
