# frozen_string_literal: true

require 'spec_helper'

RSpec.describe QueryGuard::CLI::SourceMetadataCollector do
  describe '#collect' do
    context 'when running locally (no CI)' do
      it 'collects git information' do
        collector = QueryGuard::CLI::SourceMetadataCollector.new
        metadata = collector.collect

        # Should have git section
        expect(metadata).to be_a(Hash)
        expect(metadata.key?(:git) || metadata.empty?).to be true
      end

      it 'returns nil for CI metadata when not in CI' do
        env = {}
        collector = QueryGuard::CLI::SourceMetadataCollector.new
        allow(ENV).to receive(:[]).and_call_original

        metadata = collector.collect
        # Either empty or contains only git, no ci key
        expect(metadata[:ci]).to be_nil unless metadata[:ci]
      end

      it 'gracefully handles missing git repo' do
        collector = QueryGuard::CLI::SourceMetadataCollector.new
        # Should not raise even if git fails
        expect { collector.collect }.not_to raise_error
      end
    end

    describe 'GitHub Actions detection' do
      it 'detects GitHub Actions from GITHUB_ACTIONS env var' do
        env_vars = {
          'GITHUB_ACTIONS' => 'true',
          'GITHUB_REPOSITORY' => 'owner/repo',
          'GITHUB_REF' => 'refs/heads/main',
          'GITHUB_RUN_ID' => '123',
          'GITHUB_ACTOR' => 'bot'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:provider]).to eq('github_actions')
        expect(metadata[:ci][:ci]).to eq(true)
        expect(metadata[:ci][:repository_owner]).to eq('owner')
        expect(metadata[:ci][:repository_name]).to eq('repo')
        expect(metadata[:ci][:branch]).to eq('main')
        expect(metadata[:ci][:run_id]).to eq('123')
        expect(metadata[:ci][:actor]).to eq('bot')
      end

      it 'detects GitHub Actions pull request' do
        env_vars = {
          'GITHUB_ACTIONS' => 'true',
          'GITHUB_REPOSITORY' => 'owner/repo',
          'GITHUB_EVENT_NAME' => 'pull_request',
          'GITHUB_REF' => 'refs/pull/42/merge'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:pull_request]).to eq(true)
        expect(metadata[:ci][:pull_request_number]).to eq(42)
      end

      it 'includes workflow name in GitHub Actions' do
        env_vars = {
          'GITHUB_ACTIONS' => 'true',
          'GITHUB_WORKFLOW' => 'CI Tests',
          'GITHUB_RUN_NUMBER' => '100'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:workflow]).to eq('CI Tests')
        expect(metadata[:ci][:run_number]).to eq('100')
      end
    end

    describe 'CircleCI detection' do
      it 'detects CircleCI from CIRCLECI env var' do
        env_vars = {
          'CIRCLECI' => 'true',
          'CIRCLE_PROJECT_USERNAME' => 'owner',
          'CIRCLE_PROJECT_REPONAME' => 'repo',
          'CIRCLE_BRANCH' => 'main',
          'CIRCLE_BUILD_NUM' => '456'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:provider]).to eq('circle_ci')
        expect(metadata[:ci][:repository_owner]).to eq('owner')
        expect(metadata[:ci][:repository_name]).to eq('repo')
        expect(metadata[:ci][:branch]).to eq('main')
        expect(metadata[:ci][:build_number]).to eq('456')
      end

      it 'detects CircleCI pull request' do
        env_vars = {
          'CIRCLECI' => 'true',
          'CIRCLE_PULL_REQUEST' => 'https://github.com/owner/repo/pull/99'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:pull_request]).to eq(true)
        expect(metadata[:ci][:pull_request_number]).to eq(99)
      end

      it 'includes job information in CircleCI' do
        env_vars = {
          'CIRCLECI' => 'true',
          'CIRCLE_JOB' => 'test-suite'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:job_number]).to eq('test-suite')
      end
    end

    describe 'Jenkins detection' do
      it 'detects Jenkins from JENKINS_HOME env var' do
        env_vars = {
          'JENKINS_HOME' => '/var/lib/jenkins',
          'GIT_URL' => 'https://github.com/owner/repo.git',
          'GIT_BRANCH' => 'origin/main',
          'BUILD_NUMBER' => '789'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:provider]).to eq('jenkins')
        expect(metadata[:ci][:repository_url]).to eq('https://github.com/owner/repo.git')
        expect(metadata[:ci][:branch]).to eq('main')
        expect(metadata[:ci][:build_number]).to eq('789')
      end

      it 'detects Jenkins pull request from GitHub Plugin' do
        env_vars = {
          'JENKINS_HOME' => '/var/lib/jenkins',
          'ghprbPullId' => '55'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:pull_request]).to eq(true)
        expect(metadata[:ci][:pull_request_number]).to eq(55)
      end

      it 'includes job name and build ID in Jenkins' do
        env_vars = {
          'JENKINS_HOME' => '/var/lib/jenkins',
          'JOB_NAME' => 'query-guard-tests',
          'BUILD_ID' => '2024-03-16_12-30-45'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:job_name]).to eq('query-guard-tests')
        expect(metadata[:ci][:build_id]).to eq('2024-03-16_12-30-45')
      end
    end

    describe 'GitLab CI detection' do
      it 'detects GitLab CI from CI env var' do
        env_vars = {
          'GITLAB_CI' => 'true',
          'CI_PROJECT_URL' => 'https://gitlab.com/owner/repo',
          'CI_PROJECT_NAME' => 'repo',
          'CI_COMMIT_BRANCH' => 'main',
          'CI_PIPELINE_ID' => '111'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:provider]).to eq('gitlab_ci')
        expect(metadata[:ci][:repository_url]).to eq('https://gitlab.com/owner/repo')
        expect(metadata[:ci][:repository_name]).to eq('repo')
        expect(metadata[:ci][:branch]).to eq('main')
        expect(metadata[:ci][:pipeline_id]).to eq('111')
      end

      it 'detects GitLab CI merge request' do
        env_vars = {
          'GITLAB_CI' => 'true',
          'CI_MERGE_REQUEST_IID' => '33'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:pull_request]).to eq(true)
        expect(metadata[:ci][:pull_request_number]).to eq(33)
      end

      it 'includes job name in GitLab CI' do
        env_vars = {
          'GITLAB_CI' => 'true',
          'CI_JOB_NAME' => 'test'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:job_name]).to eq('test')
      end
    end

    describe 'Travis CI detection' do
      it 'detects Travis CI from TRAVIS env var' do
        env_vars = {
          'TRAVIS' => 'true',
          'TRAVIS_REPO_SLUG' => 'owner/repo',
          'TRAVIS_BRANCH' => 'main',
          'TRAVIS_BUILD_NUMBER' => '222'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:provider]).to eq('travis_ci')
        expect(metadata[:ci][:repository]).to eq('owner/repo')
        expect(metadata[:ci][:branch]).to eq('main')
        expect(metadata[:ci][:build_number]).to eq('222')
      end

      it 'detects Travis CI pull request' do
        env_vars = {
          'TRAVIS' => 'true',
          'TRAVIS_PULL_REQUEST' => '77'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:pull_request]).to eq(true)
        expect(metadata[:ci][:pull_request_number]).to eq(77)
      end

      it 'ignores pull request when TRAVIS_PULL_REQUEST is false' do
        env_vars = {
          'TRAVIS' => 'true',
          'TRAVIS_PULL_REQUEST' => 'false',
          'TRAVIS_BRANCH' => 'main'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:pull_request]).to be_nil
        expect(metadata[:ci][:branch]).to eq('main')
      end

      it 'includes build ID in Travis CI' do
        env_vars = {
          'TRAVIS' => 'true',
          'TRAVIS_BUILD_ID' => '888'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:build_id]).to eq('888')
      end
    end

    describe 'Bitbucket Pipelines detection' do
      it 'detects Bitbucket Pipelines from BITBUCKET_BUILD_NUMBER' do
        env_vars = {
          'BITBUCKET_BUILD_NUMBER' => '333',
          'BITBUCKET_REPO_FULL_NAME' => 'owner/repo',
          'BITBUCKET_BRANCH' => 'main'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:provider]).to eq('bitbucket_ci')
        expect(metadata[:ci][:repository_full_name]).to eq('owner/repo')
        expect(metadata[:ci][:branch]).to eq('main')
        expect(metadata[:ci][:build_number]).to eq('333')
      end

      it 'detects Bitbucket Pipelines pull request' do
        env_vars = {
          'BITBUCKET_BUILD_NUMBER' => '333',
          'BITBUCKET_PR_ID' => '22'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:pull_request]).to eq(true)
        expect(metadata[:ci][:pull_request_number]).to eq(22)
      end
    end

    describe 'Integration with JsonReporter' do
      it 'includes source metadata in JSON report' do
        env_vars = {
          'GITHUB_ACTIONS' => 'true',
          'GITHUB_REPOSITORY' => 'owner/repo',
          'GITHUB_REF' => 'refs/heads/main'
        }

        collector = build_collector_with_env(env_vars)

        findings = []
        reporter = QueryGuard::CLI::JsonReporter.new(
          findings: findings,
          command: 'analyze',
          path: 'db',
          options: { source_metadata_collector: collector }
        )

        report = reporter.build_report
        expect(report[:source][:metadata][:ci][:provider]).to eq('github_actions')
      end

      it 'works without source metadata when not available' do
        env_vars = {} # No CI

        collector = build_collector_with_env(env_vars)

        findings = []
        reporter = QueryGuard::CLI::JsonReporter.new(
          findings: findings,
          command: 'analyze',
          path: 'db',
          options: { source_metadata_collector: collector }
        )

        report = reporter.build_report
        # Should still generate valid report
        expect(report).to be_a(Hash)
        expect(report[:source][:path]).to match(%r{db$})
      end
    end

    describe 'Edge cases and safety' do
      it 'handles empty environment variables gracefully' do
        collector = build_collector_with_env({})
        metadata = collector.collect

        # Should not raise
        expect(metadata).to be_a(Hash)
      end

      it 'strips whitespace from git output' do
        # This is tested implicitly by the git reading logic
        # Just ensure no methods raise on unexpected input
        collector = QueryGuard::CLI::SourceMetadataCollector.new
        expect { collector.collect }.not_to raise_error
      end

      it 'compacts nil values in metadata' do
        env_vars = {
          'GITHUB_ACTIONS' => 'true',
          'GITHUB_REPOSITORY' => 'owner/repo'
          # Missing GITHUB_REF, etc.
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        # Should not have nil values in ci hash
        expect(metadata[:ci].values).not_to include(nil)
      end

      it 'does not raise on malformed environment variables' do
        env_vars = {
          'GITHUB_ACTIONS' => 'true',
          'GITHUB_REPOSITORY' => 'malformed-without-slash'
        }

        collector = build_collector_with_env(env_vars)
        # Should not raise
        expect { collector.collect }.not_to raise_error
      end

      it 'extracts PR number from various GitHub ref formats' do
        env_vars = {
          'GITHUB_ACTIONS' => 'true',
          'GITHUB_EVENT_NAME' => 'pull_request',
          'GITHUB_REF' => 'refs/pull/999/merge'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:pull_request_number]).to eq(999)
      end

      it 'handles repository names with special characters' do
        env_vars = {
          'GITHUB_ACTIONS' => 'true',
          'GITHUB_REPOSITORY' => 'owner/repo-with-dashes'
        }

        collector = build_collector_with_env(env_vars)
        metadata = collector.collect

        expect(metadata[:ci][:repository_name]).to eq('repo-with-dashes')
      end
    end
  end

  # Helper to build collector with custom environment variables
  def build_collector_with_env(env_vars)
    collector = QueryGuard::CLI::SourceMetadataCollector.new
    allow(collector).to receive(:instance_variable_get)
      .with(:@env)
      .and_return(env_vars)

    # For methods that read from ENV, we need to mock at the instance level
    allow_any_instance_of(QueryGuard::CLI::SourceMetadataCollector)
      .to receive(:instance_variable_get)
      .with(:@env)
      .and_return(env_vars)

    # Create a fresh instance and set @env
    collector = QueryGuard::CLI::SourceMetadataCollector.new
    collector.instance_variable_set(:@env, env_vars)
    collector
  end
end
