# frozen_string_literal: true
module QueryGuard
  class Error < StandardError; end

  class Middleware
    def initialize(app, config)
      @app = app
      @config = config
    end

    def call(env)
      unless @config.enabled?(rails_env)
        return @app.call(env)
      end

      Thread.current[:query_guard_stats] = { count: 0, total_duration_ms: 0.0, violations: [] }

      status, headers, body = @app.call(env)
      check_and_report!
      [status, headers, body]
    ensure
      Thread.current[:query_guard_stats] = nil
    end

    private

    def rails_env
      if defined?(Rails) && Rails.respond_to?(:env)
        Rails.env.to_sym
      else
        (ENV["RACK_ENV"] || ENV["APP_ENV"] || "development").to_sym
      end
    end

    def logger
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger
      else
        @logger ||= Logger.new($stdout)
      end
    end

    def check_and_report!
      stats = Thread.current[:query_guard_stats] || { count: 0, violations: [] }
      violations = stats[:violations].dup

      if @config.max_queries_per_request && stats[:count] > @config.max_queries_per_request
        violations << { type: :too_many_queries, count: stats[:count], limit: @config.max_queries_per_request }
      end

      return if violations.empty?

      message = format_message(stats, violations)
      logger.warn(message)

      raise QueryGuard::Error, message if @config.raise_on_violation
    end

    def format_message(stats, violations)
      details = violations.map do |v|
        case v[:type]
        when :too_many_queries
          "too_many_queries: count=#{v[:count]} limit=#{v[:limit]}"
        when :slow_query
          "slow_query: #{v[:duration_ms]}ms SQL=#{truncate_sql(v[:sql])}"
        when :select_star
          "select_star: SQL=#{truncate_sql(v[:sql])}"
        else
          v[:type].to_s
        end
      end.join(" | ")

      "#{@config.log_prefix} queries=#{stats[:count]} total_ms=#{stats[:total_duration_ms].round(2)} | #{details}"
    end

    def truncate_sql(sql, max = 200)
      sql.length > max ? "#{sql[0, max]}..." : sql
    end
  end
end
