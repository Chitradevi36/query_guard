# frozen_string_literal: true
module QueryGuard
  class Config
    attr_accessor :enabled_environments, :max_queries_per_request,
                  :max_duration_ms_per_query, :block_select_star,
                  :ignored_sql, :raise_on_violation, :log_prefix,
                  :base_url, :api_key, :project, :env

    def initialize
      @enabled_environments     = %i[development test]
      @max_queries_per_request  = 100
      @max_duration_ms_per_query = 100.0   # ms; set to nil to disable
      @block_select_star        = false
      @ignored_sql              = [/^PRAGMA /i, /^BEGIN/i, /^COMMIT/i]
      @raise_on_violation       = false
      @log_prefix               = "[QueryGuard]"
    end

    def enabled?(env)
      @enabled_environments.map(&:to_sym).include?(env.to_sym)
    end
  end
end
