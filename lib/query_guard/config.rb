# frozen_string_literal: true
require "query_guard/analyzers/base"
require "query_guard/analyzers/registry"
require "query_guard/analyzers/slow_query_analyzer"
require "query_guard/analyzers/query_count_analyzer"
require "query_guard/analyzers/select_star_analyzer"
require "query_guard/analyzers/query_risk_analyzer"
require_relative "budget"

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

    # --- Security features ---
    attr_accessor :enable_security
    attr_accessor :detect_sql_injection
    attr_accessor :sql_injection_patterns

    attr_accessor :detect_unusual_query_pattern
    attr_accessor :max_queries_per_minute_per_actor
    attr_accessor :max_unique_query_fingerprints_per_minute_per_actor

    attr_accessor :detect_data_exfiltration
    attr_accessor :max_response_bytes_per_request
    attr_accessor :exfiltration_path_regex

    attr_accessor :detect_mass_assignment
    attr_accessor :sensitive_param_keys

    # Actor resolver for rate limiting (ip/user/token)
    attr_accessor :actor_resolver

    # Storage for rolling counters (defaults to in-memory)
    attr_accessor :store

    # Budget system
    attr_reader :budget

    def initialize
      # User-facing configuration - simplified for new users
      @migrations_directory     = "db/migrate"
      @enabled_environments     = %i[development test]

      # Query monitoring thresholds
      @max_queries_per_request  = 100
      @max_duration_ms_per_query = 100.0
      @block_select_star        = false
      @raise_on_violation       = false
      @ignored_sql              = [/^PRAGMA /i, /^BEGIN/i, /^COMMIT/i]
      @log_prefix               = "[QueryGuard]"

      # Analyzer registry and control
      @disabled_analyzers       = []
      @analyzer_registry        = Analyzers::Registry.new
      @analyze_query_risks      = true
      @use_explain_plans        = false
      @explain_enricher         = nil

      # Analyzer severity levels
      @slow_query_severity      = :warn
      @query_count_severity     = :warn
      @select_star_severity     = :warn
      @migration_risk_severity  = :error

      # --- Security defaults (safe, low noise) ---
      @enable_security          = true
      @detect_sql_injection     = true
      @sql_injection_patterns   = [
        /(\bor\b|\band\b)\s+\d+\s*=\s*\d+/i,   # OR 1=1
        /\bunion\s+select\b/i,
        /--|\/\*|\*\//,                         # comment tokens
        /;\s*(drop|alter|truncate)\b/i,
        /\b(pg_sleep|sleep)\s*\(/i,
        /\binformation_schema\b/i
      ]

      @detect_unusual_query_pattern = true
      @max_queries_per_minute_per_actor = 300
      @max_unique_query_fingerprints_per_minute_per_actor = 80

      @detect_data_exfiltration = true
      @max_response_bytes_per_request = 2_000_000 # ~2MB
      @exfiltration_path_regex = %r{/(export|download|reports|dump)\b}i

      @detect_mass_assignment   = true
      @sensitive_param_keys     = %w[
        admin is_admin role roles permissions permission account_id user_id
        plan_id price amount balance credit debit status state
      ]

      @actor_resolver = lambda do |env|
        env["query_guard.actor"] ||
          env["action_dispatch.remote_ip"]&.to_s ||
          env["REMOTE_ADDR"]&.to_s ||
          "unknown"
      end

      @store = nil # will default to QueryGuard::Store.new

      @export_mode              = :async
      @export_queries           = :all
      @max_query_events_per_req = 200
      @origin_app               = nil

      # Budget system
      @budget = Budget.new

      # Uploader configuration (SaaS ingestion, future feature)
      @uploader_type            = 'no-op'
      @api_base_url             = nil
      @project_key              = nil
      @api_token                = nil

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
