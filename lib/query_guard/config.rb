# frozen_string_literal: true
require "query_guard/analyzers/base"
require "query_guard/analyzers/registry"
require "query_guard/analyzers/slow_query_analyzer"
require "query_guard/analyzers/query_count_analyzer"
require "query_guard/analyzers/select_star_analyzer"
require "query_guard/analyzers/query_risk_analyzer"

module QueryGuard
  class Config
    # User-facing configuration
    attr_accessor :migrations_directory, :enabled_environments

    # Analyzer control
    attr_accessor :disabled_analyzers

    # Severity levels for analyzers
    attr_accessor :slow_query_severity, :query_count_severity,
                  :select_star_severity, :migration_risk_severity

    # Query monitoring (optional, defaults disabled)
    attr_accessor :max_queries_per_request, :max_duration_ms_per_query,
                  :block_select_star, :raise_on_violation,
                  :analyze_query_risks,  # Enable/disable query risk analysis
                  :use_explain_plans,    # Use EXPLAIN plans for query analysis
                  :explain_enricher,     # Custom EXPLAIN enricher
                  :ignored_sql           # SQL patterns to ignore in analysis

    # Uploader configuration (SaaS ingestion, future feature)
    attr_accessor :uploader_type, :api_base_url, :project_key, :api_token

    attr_reader :analyzer_registry

    def initialize
      # User-facing configuration - simplified for new users
      @migrations_directory     = "db/migrate"  # Rails default
      @enabled_environments     = %i[development test]

      # Internal analyzer control
      @disabled_analyzers       = []
      @analyzer_registry        = Analyzers::Registry.new

      # Severity levels for each analyzer (what warnings to display)
      @slow_query_severity      = :warn
      @query_count_severity     = :warn
      @select_star_severity     = :warn
      @migration_risk_severity  = :error

      # Query monitoring thresholds (optional)
      @max_queries_per_request  = 100
      @max_duration_ms_per_query = 100.0
      @block_select_star        = false
      @raise_on_violation       = false
      @analyze_query_risks      = true  # Enable query risk analysis by default
      @use_explain_plans        = false # EXPLAIN plans disabled by default
      @explain_enricher         = nil   # No custom enricher by default
      @ignored_sql              = []    # SQL patterns to ignore

      # Uploader configuration (SaaS ingestion, future feature)
      @uploader_type            = 'no-op'  # Default: no upload
      @api_base_url             = nil      # Future: https://api.queryguard.example.com
      @project_key              = nil      # Future: project-123
      @api_token                = nil      # Future: secret-api-token

      # Register default analyzers
      @analyzer_registry.register(:slow_query, Analyzers::SlowQueryAnalyzer.new)
      @analyzer_registry.register(:query_count, Analyzers::QueryCountAnalyzer.new)
      @analyzer_registry.register(:select_star, Analyzers::SelectStarAnalyzer.new)
      @analyzer_registry.register(:query_risk, Analyzers::QueryRiskAnalyzer.new)
    end

    def enabled?(env)
      @enabled_environments.map(&:to_sym).include?(env.to_sym)
    end

    # Disable a specific analyzer by name
    def disable_analyzer(name)
      analyzer_sym = name.to_sym
      @disabled_analyzers << analyzer_sym unless @disabled_analyzers.include?(analyzer_sym)
    end

    # Enable a previously disabled analyzer
    def enable_analyzer(name)
      @disabled_analyzers.delete(name.to_sym)
    end

    # Register a custom analyzer
    def register_analyzer(name, analyzer)
      @analyzer_registry.register(name, analyzer)
    end
  end
end
