# frozen_string_literal: true

module QueryGuard
  module Core
    # Immutable representation of a single SQL query event.
    # Captured from ActiveSupport::Notifications sql.active_record event.
    class Query
      attr_reader :sql, :duration_ms, :name, :started_at, :finished_at

      def initialize(sql:, duration_ms:, name: nil, started_at: nil, finished_at: nil)
        @sql = sql.freeze
        @duration_ms = duration_ms
        @name = name.to_s.freeze if name
        @started_at = started_at
        @finished_at = finished_at
      end

      # Serialize to hash for reporting
      def to_h
        {
          sql: sql,
          duration_ms: duration_ms,
          name: name,
          started_at: started_at&.iso8601,
          finished_at: finished_at&.iso8601
        }
      end

      def inspect
        "#<Query duration_ms=#{duration_ms} sql='#{truncate_sql(sql, 50)}'>"
      end

      private

      def truncate_sql(sql, length = 100)
        sql.length > length ? "#{sql[0, length]}..." : sql
      end
    end
  end
end
