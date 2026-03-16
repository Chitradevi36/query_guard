# frozen_string_literal: true

module QueryGuard
  module Explain
    # Base interface for database-specific EXPLAIN plan adapters.
    # Implementations should handle:
    # - Safe query execution without side effects
    # - Plan data extraction in JSON format
    # - Graceful error handling
    #
    # Example:
    #   adapter = PostgreSQLAdapter.new(connection)
    #   plan = adapter.get_plan("SELECT * FROM users")
    #   # => { "Plan" => { "Node Type" => "Seq Scan", ... }, ... }
    class AdapterInterface
      # Initialize adapter with database connection
      #
      # @param connection [Object] Database-specific connection object
      def initialize(connection)
        @connection = connection
      end

      # Get EXPLAIN plan for a query (JSON format when possible)
      #
      # @param sql [String] SQL query to analyze
      # @param options [Hash] Adapter-specific options
      # @return [Hash] Parsed plan JSON or nil if unavailable
      # @raise [QueryGuard::Explain::AdapterError] on execution failure
      #
      # Example return structure (PostgreSQL):
      #   {
      #     "Plan" => {
      #       "Node Type" => "Seq Scan",
      #       "Relation Name" => "users",
      #       "Plans" => [...],
      #       "Actual Rows" => 100,
      #       "Actual Total Time" => 2.543
      #     },
      #     "Planning Time" => 0.234,
      #     "Execution Time" => 2.543
      #   }
      def get_plan(sql, options = {})
        raise NotImplementedError, "Subclasses must implement get_plan"
      end

      # Check if adapter can execute EXPLAIN for this query type
      #
      # @param sql [String] SQL query
      # @return [Boolean] True if EXPLAIN is supported
      def can_explain?(sql)
        raise NotImplementedError, "Subclasses must implement can_explain?"
      end

      # Get engine name for this adapter
      #
      # @return [Symbol] Engine identifier (:postgresql, :mysql, etc.)
      def engine_name
        raise NotImplementedError, "Subclasses must implement engine_name"
      end

      protected

      attr_reader :connection
    end

    # Custom error for EXPLAIN-related failures
    class AdapterError < StandardError
      attr_reader :query, :original_error

      def initialize(message, query: nil, original_error: nil)
        super(message)
        @query = query
        @original_error = original_error
      end
    end

    # Raised when EXPLAIN execution is not supported for a query
    class UnsupportedQueryError < AdapterError; end

    # Raised when connection is unavailable
    class ConnectionError < AdapterError; end

    # Raised when query execution times out
    class TimeoutError < AdapterError; end

    # Raised when EXPLAIN plan parsing fails
    class PlanParseError < AdapterError; end
  end
end
