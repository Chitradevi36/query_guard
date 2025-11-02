# frozen_string_literal: true
require "active_support/notifications"

module QueryGuard
  module Subscriber
    SQL_EVENT = "sql.active_record"

    def self.install!(config)
      return if @installed
      @config = config
      @subscriber = ActiveSupport::Notifications.subscribe(SQL_EVENT) do |_, started, finished, _, payload|
        stats = Thread.current[:query_guard_stats]
        next unless stats # only track inside our middleware window

        # Skip schema and ignored
        name = payload[:name].to_s
        next if name == "SCHEMA"

        sql = payload[:sql].to_s
        next if config.ignored_sql.any? { |r| r === sql }

        duration_ms = (finished - started) * 1000.0
        stats[:count] += 1
        stats[:total_duration_ms] += duration_ms

        if config.max_duration_ms_per_query && duration_ms > config.max_duration_ms_per_query
          stats[:violations] << {
            type: :slow_query,
            duration_ms: duration_ms.round(2),
            sql: sql
          }
        end

        if config.block_select_star && sql =~ /\bSELECT\s+\*/i
          stats[:violations] << { type: :select_star, sql: sql }
        end
      end
      @installed = true
    end

    def self.uninstall!
      return unless @installed && @subscriber
      ActiveSupport::Notifications.unsubscribe(@subscriber)
      @installed = false
      @subscriber = nil
    end
  end
end
