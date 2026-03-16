# frozen_string_literal: true

module QueryGuard
  class CLI
    # Collects source and CI environment metadata for SaaS dashboards and PR views.
    #
    # Captures:
    # - Git information (SHA, branch, repository name)
    # - CI provider detection (GitHub Actions, CircleCI, Jenkins, etc.)
    # - Pull request information when available
    # - Graceful fallbacks for local development
    #
    # Design:
    # - Modular detection for each CI provider
    # - Fails gracefully (returns what's available)
    # - No external dependencies (pure stdlib)
    # - Suitable for SaaS platform ingestion
    #
    # Example:
    #   collector = QueryGuard::CLI::SourceMetadataCollector.new
    #   metadata = collector.collect
    #   # => { git: { sha: '...' }, ci: { provider: 'github_actions', ... } }
    class SourceMetadataCollector
      def initialize
        @env = ENV.to_h
      end

      # Collect all available source and CI metadata
      # Returns: Hash with git and ci information
      def collect
        {
          git: collect_git_metadata,
          ci: collect_ci_metadata
        }.compact
      end

      private

      # Collect git information
      # SHA, branch, repository name
      def collect_git_metadata
        git_info = {}

        # Git SHA (commit hash)
        git_info[:sha] = read_git_sha
        git_info[:branch] = read_git_branch
        git_info[:repository] = read_git_repository

        # Only include if we found at least the SHA
        git_info.empty? ? nil : git_info.compact
      end

      # Detect CI provider and collect CI-specific metadata
      def collect_ci_metadata
        case ci_provider
        when :github_actions
          detect_github_actions_metadata
        when :circle_ci
          detect_circle_ci_metadata
        when :jenkins
          detect_jenkins_metadata
        when :gitlab_ci
          detect_gitlab_ci_metadata
        when :travis_ci
          detect_travis_ci_metadata
        when :bitbucket_ci
          detect_bitbucket_ci_metadata
        else
          # Local development or unknown CI
          nil
        end
      end

      # Detect which CI provider is running
      def ci_provider
        return :github_actions if @env['GITHUB_ACTIONS'] == 'true'
        return :circle_ci if @env['CIRCLECI'] == 'true'
        return :jenkins if @env['JENKINS_HOME']
        return :gitlab_ci if @env['GITLAB_CI'] == 'true'
        return :travis_ci if @env['TRAVIS'] == 'true'
        return :bitbucket_ci if @env['BITBUCKET_BUILD_NUMBER']

        nil
      end

      # Github Actions metadata
      def detect_github_actions_metadata
        metadata = {
          provider: 'github_actions',
          ci: true
        }

        # Repository
        if @env['GITHUB_REPOSITORY']
          owner, repo = @env['GITHUB_REPOSITORY'].split('/')
          metadata[:repository_owner] = owner
          metadata[:repository_name] = repo
        end

        # Pull request information
        if @env['GITHUB_EVENT_NAME'] == 'pull_request'
          metadata[:pull_request_number] = @env['GITHUB_REF']&.match(/refs\/pull\/(\d+)\/merge/)&.captures&.first&.to_i
          metadata[:pull_request] = true
        elsif @env['GITHUB_REF']
          metadata[:branch] = @env['GITHUB_REF'].sub('refs/heads/', '')
        end

        # Run information
        metadata[:run_id] = @env['GITHUB_RUN_ID']
        metadata[:run_number] = @env['GITHUB_RUN_NUMBER']
        metadata[:actor] = @env['GITHUB_ACTOR']
        metadata[:workflow] = @env['GITHUB_WORKFLOW']

        metadata.compact
      end

      # CircleCI metadata
      def detect_circle_ci_metadata
        metadata = {
          provider: 'circle_ci',
          ci: true
        }

        # Repository
        metadata[:repository_owner] = @env['CIRCLE_PROJECT_USERNAME']
        metadata[:repository_name] = @env['CIRCLE_PROJECT_REPONAME']

        # Branch
        metadata[:branch] = @env['CIRCLE_BRANCH']

        # Pull request information
        if @env['CIRCLE_PULL_REQUEST']
          metadata[:pull_request_number] = @env['CIRCLE_PULL_REQUEST'].match(/\/(\d+)$/)&.captures&.first&.to_i
          metadata[:pull_request] = true
        end

        # Run information
        metadata[:build_number] = @env['CIRCLE_BUILD_NUM']
        metadata[:job_number] = @env['CIRCLE_JOB']

        metadata.compact
      end

      # Jenkins metadata
      def detect_jenkins_metadata
        metadata = {
          provider: 'jenkins',
          ci: true
        }

        # Repository and branch
        metadata[:repository_url] = @env['GIT_URL']
        metadata[:branch] = @env['GIT_BRANCH']&.sub('origin/', '')

        # Pull request information (from GitHub Plugin)
        if @env['ghprbPullId']
          metadata[:pull_request_number] = @env['ghprbPullId'].to_i
          metadata[:pull_request] = true
        end

        # Build information
        metadata[:build_number] = @env['BUILD_NUMBER']
        metadata[:build_id] = @env['BUILD_ID']
        metadata[:job_name] = @env['JOB_NAME']

        metadata.compact
      end

      # GitLab CI metadata
      def detect_gitlab_ci_metadata
        metadata = {
          provider: 'gitlab_ci',
          ci: true
        }

        # Repository
        metadata[:repository_url] = @env['CI_PROJECT_URL']
        metadata[:repository_name] = @env['CI_PROJECT_NAME']

        # Branch and merge request
        if @env['CI_MERGE_REQUEST_IID']
          metadata[:pull_request_number] = @env['CI_MERGE_REQUEST_IID'].to_i
          metadata[:pull_request] = true
        else
          metadata[:branch] = @env['CI_COMMIT_BRANCH']
        end

        # Pipeline information
        metadata[:pipeline_id] = @env['CI_PIPELINE_ID']
        metadata[:job_name] = @env['CI_JOB_NAME']

        metadata.compact
      end

      # Travis CI metadata
      def detect_travis_ci_metadata
        metadata = {
          provider: 'travis_ci',
          ci: true
        }

        # Repository
        metadata[:repository] = @env['TRAVIS_REPO_SLUG']

        # Branch and pull request
        if @env['TRAVIS_PULL_REQUEST'] && @env['TRAVIS_PULL_REQUEST'] != 'false'
          metadata[:pull_request_number] = @env['TRAVIS_PULL_REQUEST'].to_i
          metadata[:pull_request] = true
        else
          metadata[:branch] = @env['TRAVIS_BRANCH']
        end

        # Build information
        metadata[:build_number] = @env['TRAVIS_BUILD_NUMBER']
        metadata[:build_id] = @env['TRAVIS_BUILD_ID']

        metadata.compact
      end

      # Bitbucket Pipelines metadata
      def detect_bitbucket_ci_metadata
        metadata = {
          provider: 'bitbucket_ci',
          ci: true
        }

        # Repository
        metadata[:repository_full_name] = @env['BITBUCKET_REPO_FULL_NAME']

        # Branch
        metadata[:branch] = @env['BITBUCKET_BRANCH']

        # Pull request information
        if @env['BITBUCKET_PR_ID']
          metadata[:pull_request_number] = @env['BITBUCKET_PR_ID'].to_i
          metadata[:pull_request] = true
        end

        # Build information
        metadata[:build_number] = @env['BITBUCKET_BUILD_NUMBER']

        metadata.compact
      end

      # Read git SHA (commit hash)
      # Returns: String (40-char hex) or nil
      def read_git_sha
        read_git_config('rev-parse', 'HEAD')
      end

      # Read current git branch
      # Returns: String branch name or nil
      def read_git_branch
        # Try to get from detached HEAD first
        ref = read_git_config('symbolic-ref', '--short', 'HEAD')
        return ref if ref

        # Fallback: try to get from rev-parse
        read_git_config('rev-parse', '--abbrev-ref', 'HEAD')
      end

      # Read repository name from git remote
      # Returns: String repository name or nil
      def read_git_repository
        url = read_git_config('remote', 'get-url', 'origin')
        return nil unless url

        # Extract repo name from URL
        # Handles: https://github.com/owner/repo.git, git@github.com:owner/repo.git, etc.
        url.match(%r{(?:https://|git@)?(?:.*?)[:/](.+?)(?:\.git)?/?$})&.captures&.first
      end

      # Execute git command and return output
      # Fails silently if git not available or not a git repo
      def read_git_config(*git_args)
        require 'open3'

        # Check if we're in a git repository
        return nil unless Dir.exist?('.git') || system('git rev-parse --git-dir > /dev/null 2>&1')

        begin
          stdout, status = Open3.capture2('git', *git_args)
          return nil unless status.success?

          output = stdout.strip
          output.empty? ? nil : output
        rescue Errno::ENOENT
          # git command not found
          nil
        rescue StandardError
          # Any other error (permission denied, etc.)
          nil
        end
      end
    end
  end
end
