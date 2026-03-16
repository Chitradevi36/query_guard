# frozen_string_literal: true

module QueryGuard
  module Migrations
    # Abstract interface for database metadata adapters.
    #
    # Adapters implement this interface to provide table metadata
    # (row counts, lock behavior, etc.) from different database systems.
    #
    # Example:
    #   adapter = PostgreSQLAdapter.new(connection)
    #   rows = adapter.estimate_table_rows(:users)
    #
    # Adapters should:
    # 1. Handle connection failures gracefully
    # 2. Return nil or empty hash if data unavailable
    # 3. Cache results where possible
    # 4. Never raise exceptions during metadata queries
    class DatabaseAdapter
      # Get estimated row count for a table
      #
      # @param table_name [String, Symbol] Name of the table
      # @return [Integer, nil] Estimated number of rows, or nil if unavailable
      def estimate_table_rows(table_name)
        raise NotImplementedError, "Subclasses must implement estimate_table_rows"
      end

      # Get lock impact estimate for a table
      #
      # Scores table's lock risk based on size and activity.
      # Based on PostgreSQL's vacuum and maintenance overhead.
      #
      # @param table_name [String, Symbol] Name of the table
      # @return [Symbol, nil] Risk level: :low, :medium, :high, :critical
      def estimate_lock_risk(table_name)
        raise NotImplementedError, "Subclasses must implement estimate_lock_risk"
      end

      # Check if table exists in database
      #
      # @param table_name [String, Symbol] Name of the table
      # @return [Boolean] True if table exists
      def table_exists?(table_name)
        raise NotImplementedError, "Subclasses must implement table_exists?"
      end

      # Get all table names in current schema
      #
      # @return [Array<String>] List of table names
      def list_tables
        raise NotImplementedError, "Subclasses must implement list_tables"
      end

      # Check if connection is healthy
      #
      # @return [Boolean] True if adapter can query database
      def connected?
        raise NotImplementedError, "Subclasses must implement connected?"
      end
    end

    # NoOp adapter that always returns unavailable
    #
    # Used when no database connection is configured.
    # Gracefully disables database-aware analysis.
    class NullDatabaseAdapter < DatabaseAdapter
      def estimate_table_rows(table_name)
        nil
      end

      def estimate_lock_risk(table_name)
        nil
      end

      def table_exists?(table_name)
        false
      end

      def list_tables
        []
      end

      def connected?
        false
      end
    end
  end
end
