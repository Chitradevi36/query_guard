# frozen_string_literal: true
module QueryGuard
  class Config
    attr_accessor :enabled_environments, :max_queries_per_request,
                  :max_duration_ms_per_query, :block_select_star,
                  :ignored_sql, :raise_on_violation, :log_prefix,
                  :base_url, :api_key, :project, :env

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

    def initialize
      @enabled_environments      = %i[development test]
      @max_queries_per_request   = 100
      @max_duration_ms_per_query = 100.0
      @block_select_star         = false
      @ignored_sql               = [/^PRAGMA /i, /^BEGIN/i, /^COMMIT/i]
      @raise_on_violation        = false
      @log_prefix                = "[QueryGuard]"

      # --- Security defaults (safe, low noise) ---
      @enable_security = true

      @detect_sql_injection = true
      @sql_injection_patterns = [
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

      @detect_mass_assignment = true
      @sensitive_param_keys = %w[
        admin is_admin role roles permissions permission account_id user_id
        plan_id price amount balance credit debit status state
      ]

      @actor_resolver = lambda do |env|
        # Prefer authenticated user id if app sets it
        env["query_guard.actor"] ||
          env["action_dispatch.remote_ip"]&.to_s ||
          env["REMOTE_ADDR"]&.to_s ||
          "unknown"
      end

      @store = nil # will default to QueryGuard::Store.new

      @export_mode              = :async
      @export_queries            = :all
      @max_query_events_per_req  = 200
      @origin_app                = nil
    end

    def enabled?(env)
      @enabled_environments.map(&:to_sym).include?(env.to_sym)
    end
  end
end
