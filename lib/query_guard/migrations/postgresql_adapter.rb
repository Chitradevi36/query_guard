# frozen_string_literal: true

module QueryGuard
  module Migrations
    # PostgreSQL-specific metadata adapter
    #
    # Queries PostgreSQL system catalog to estimate table sizes
    # and determine lock risk based on row count and write activity.
    #
    # Row count thresholds (from PostgreSQL best practices):
    # - < 1M rows: Low lock risk, fast schema changes
    # - 1M - 10M rows: Medium lock risk, monitor lock times
    # - 10M - 100M rows: High lock risk, use concurrent operations
    # - > 100M rows: Critical risk, requires special handling
    class PostgreSQLAdapter < DatabaseAdapter
      # Lock duration thresholds (milliseconds)
      # Based on typical PostgreSQL behavior
      LOCK_THRESHOLDS = {
        low: 1_000_000,        # < 1M rows
        medium: 10_000_000,    # 1M - 10M rows
        high: 100_000_000,     # 10M - 100M rows
        critical: Float::INFINITY  # > 100M rows
      }.freeze

      # Initialize PostgreSQL adapter
      #
      # @param connection [Object] Active database connection (responds to exec_query)
      # @param schema [String] Schema to query (default: public)
      # @option cache [Boolean] Whether to cache row count queries (default: true)
      def initialize(connection, schema: "public", cache: true)
        @connection = connection
        @schema = schema
        @cache_enabled = cache
        @cache = {} if cache
      end

      # Estimate row count using PostgreSQL statistics
      #
      # Uses pg_class.reltuples for estimated row count.
      # Falls back to COUNT(*) if stats unavailable.
      #
      # @param table_name [String, Symbol] Table name
      # @return [Integer, nil] Estimated rows, or nil if unavailable
      def estimate_table_rows(table_name)
        return nil unless connected?
        return @cache[table_name.to_s] if @cache_enabled && @cache.key?(table_name.to_s)

        begin
          # Use PostgreSQL statistics (faster, less accurate)
          result = @connection.exec_query(
            "SELECT reltuples::bigint as estimated_rows FROM pg_class
             WHERE relname = $1 AND relnamespace = 
               (SELECT oid FROM pg_namespace WHERE nspname = $2)
             LIMIT 1",
            "GetTableRows",
            [[table_name.to_s, :string], [@schema, :string]]
          )

          rows = result.rows.dig(0, 0)&.to_i
          @cache[table_name.to_s] = rows if @cache_enabled
          rows
        rescue StandardError => e
          # Fail gracefully - log if possible, return nil
          warn "Failed to get row count for #{table_name}: #{e.message}"
          nil
        end
      end

      # Estimate lock risk based on table size
      #
      # Larger tables take longer to lock and rewrite,
      # increasing risk of production impact.
      #
      # @param table_name [String, Symbol] Table name
      # @return [Symbol, nil] Risk level: :low, :medium, :high, :critical
      def estimate_lock_risk(table_name)
        rows = estimate_table_rows(table_name)
        return nil if rows.nil?

        case rows
        when 0...LOCK_THRESHOLDS[:low]
          :low
        when LOCK_THRESHOLDS[:low]...LOCK_THRESHOLDS[:medium]
          :medium
        when LOCK_THRESHOLDS[:medium]...LOCK_THRESHOLDS[:high]
          :high
        else
          :critical
        end
      end

      # Check if table exists
      #
      # @param table_name [String, Symbol] Table name
      # @return [Boolean] True if table exists in schema
      def table_exists?(table_name)
        return false unless connected?

        begin
          result = @connection.exec_query(
            "SELECT 1 FROM information_schema.tables
             WHERE table_schema = $1 AND table_name = $2 LIMIT 1",
            "CheckTableExists",
            [[@schema, :string], [table_name.to_s, :string]]
          )
          result.rows.any?
        rescue StandardError => e
          warn "Failed to check if table exists #{table_name}: #{e.message}"
          false
        end
      end

      # List all tables in schema
      #
      # @return [Array<String>] Table names
      def list_tables
        return [] unless connected?

        begin
          result = @connection.exec_query(
            "SELECT table_name FROM information_schema.tables
             WHERE table_schema = $1
             ORDER BY table_name",
            "ListTables",
            [[@schema, :string]]
          )
          result.rows.flatten
        rescue StandardError => e
          warn "Failed to list tables: #{e.message}"
          []
        end
      end

      # Check if connection is healthy
      #
      # @return [Boolean] True if we can query the database
      def connected?
        return false if @connection.nil?

        begin
          @connection.exec_query("SELECT 1 LIMIT 1")
          true
        rescue StandardError => e
          warn "Database connection check failed: #{e.message}"
          false
        end
      end

      # Clear the row count cache
      #
      # Call this if you've made schema changes and want fresh stats.
      def clear_cache
        @cache.clear if @cache_enabled && @cache
      end
    end
  end
end
