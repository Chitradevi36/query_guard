# frozen_string_literal: true
require "active_support/notifications"
require "query_guard/security"

module QueryGuard
  module Subscriber
    SQL_EVENT = "sql.active_record"

    def self.install!(config)
      return if @installed

      @subscriber = ActiveSupport::Notifications.subscribe(SQL_EVENT) do |_, started, finished, _, payload|
        stats = Thread.current[:query_guard_stats]
        next unless stats

        name = payload[:name].to_s
        next if name == "SCHEMA"

        sql = payload[:sql].to_s
        next if config.ignored_sql.any? { |r| r === sql }

        duration_ms = (finished - started) * 1000.0
        stats[:count] += 1
        stats[:total_duration_ms] += duration_ms

        fp = QueryGuard::Security.fingerprint(sql)
        stats[:fingerprints][fp] += 1

        if config.max_duration_ms_per_query && duration_ms > config.max_duration_ms_per_query
          stats[:violations] << { type: :slow_query, duration_ms: duration_ms.round(2), sql: sql }
        end

        if config.block_select_star && sql =~ /\bSELECT\s+\*/i
          stats[:violations] << { type: :select_star, sql: sql }
        end

        # --- SQL Injection detection ---
        if config.enable_security && config.detect_sql_injection
          if QueryGuard::Security.suspicious_sql_injection?(sql, config.sql_injection_patterns)
            stats[:violations] << { type: :sql_injection_suspected, sql: sql }
          end
        end

        # --- Data exfiltration query-shape heuristic ---
        if config.enable_security && config.detect_data_exfiltration
          if QueryGuard::Security.possible_exfiltration_query?(sql)
            stats[:violations] << { type: :possible_data_exfiltration_query, sql: sql }
          end
        end

        max = config.max_query_events_per_req || 200
        if stats[:queries].length < max
          stats[:queries] << {
            sql: sql,
            duration_ms: duration_ms.round(2),
            occurred_at: Time.now.utc.iso8601
          }
        end
      end

      @installed = true
    end
  end
end
