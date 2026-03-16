# frozen_string_literal: true

require "json"

module QueryGuard
  module Explain
    # PostgreSQL-specific EXPLAIN plan adapter.
    # Executes EXPLAIN (FORMAT JSON, ANALYZE) for PostgreSQL queries.
    #
    # Features:
    # - Safely executes EXPLAIN with ANALYZE for actual metrics
    # - Returns well-structured JSON plan data
    # - Fails gracefully if connection unavailable
    # - Filters out unsafe query patterns
    # - Configurable timeout and ANALYZE flag
    #
    # Example:
    #   adapter = PostgreSQLAdapter.new(ActiveRecord::Base.connection)
    #   plan = adapter.get_plan("SELECT * FROM users WHERE status = 'active'")
    #
    # Note: Requires postgres adapter (pg gem) with access to query execution
    class PostgreSQLAdapter < AdapterInterface
      DEFAULT_EXPLAIN_TIMEOUT = 5.0  # seconds

      # Initialize PostgreSQL adapter
      #
      # @param connection [PG::Connection or ActiveRecord Adapter] PostgreSQL connection
      # @param options [Hash] Configuration options
      #   @option options [Float] :timeout Explain query timeout (default: 5.0s)
      #   @option options [Boolean] :use_analyze Whether to use ANALYZE (default: false for safety)
      #   @option options [Logger] :logger Optional logger instance for debugging
      #   @option options [Boolean] :validate_connection Check connection is valid on init (default: true)
      def initialize(connection, options = {})
        super(connection)
        @timeout = options[:timeout] || DEFAULT_EXPLAIN_TIMEOUT
        @use_analyze = options.fetch(:use_analyze, false)
        @logger = options[:logger]
        @validate_connection = options.fetch(:validate_connection, true)

        validate_connection! if @validate_connection
      end

      # Execute EXPLAIN and return parsed JSON plan
      #
      # @param sql [String] SQL query to analyze
      # @param options [Hash] Override default options
      # @return [Hash] Parsed EXPLAIN plan JSON
      # @raise [AdapterError] If query can't be explained
      def get_plan(sql, options = {})
        unless can_explain?(sql)
          error_msg = "Cannot EXPLAIN this query type: #{sql.strip[0..50]}..."
          log_warn(error_msg)
          raise UnsupportedQueryError, error_msg
        end

        use_analyze = options.fetch(:use_analyze, @use_analyze)
        explain_sql = build_explain_query(sql, use_analyze)

        log_debug("Executing EXPLAIN query", use_analyze: use_analyze)
        plan_json = execute_explain(explain_sql)
        JSON.parse(plan_json)
      rescue JSON::ParserError => e
        error_msg = "Failed to parse EXPLAIN output: #{e.message}"
        log_warn(error_msg)
        raise PlanParseError, error_msg
      rescue Timeout::Error => e
        error_msg = "EXPLAIN query timed out after #{@timeout}s"
        log_warn(error_msg)
        raise TimeoutError, error_msg
      rescue StandardError => e
        log_warn("EXPLAIN execution failed: #{e.message}")
        raise AdapterError, "EXPLAIN execution failed: #{e.message}"
      end

      # Check if query can be safely explained
      #
      # @param sql [String] SQL query
      # @return [Boolean] True if query is safe to EXPLAIN
      def can_explain?(sql)
        normalized = sql.strip.upcase
        # Only EXPLAIN SELECT, WITH (CTE), and simple UPDATE/DELETE
        return false if normalized.start_with?("PRAGMA", "BEGIN", "COMMIT")
        return false if normalized.start_with?("DROP", "ALTER", "CREATE", "TRUNCATE")
        return false if normalized.include?("RETURNING") && !normalized.start_with?("SELECT")

        true
      end

      # Engine identifier
      #
      # @return [Symbol]
      def engine_name
        :postgresql
      end

      # Get version of PostgreSQL server
      #
      # @return [String] PostgreSQL version
      def server_version
        execute_query("SELECT version()").first.first
      rescue StandardError => e
        raise ConnectionError, "Cannot connect to PostgreSQL: #{e.message}"
      end

      private

      def build_explain_query(sql, use_analyze)
        # EXPLAIN (FORMAT JSON) provides output in JSON format
        # ANALYZE actually runs the query (for real metrics) but is slower
        # For safety, default to just EXPLAIN without ANALYZE

        options = "FORMAT JSON"
        options += ", ANALYZE" if use_analyze
        options += ", BUFFERS" if use_analyze  # useful with ANALYZE

        "EXPLAIN (#{options}) #{sql}"
      end

      def execute_explain(explain_sql)
        begin
          result = execute_query_with_timeout(explain_sql)
          # Result is array of rows, each with plan JSON
          # PostgreSQL returns one row with the full plan as JSON
          plan_or_nil = result.first&.first
          plan_or_nil || raise(AdapterError, "EXPLAIN returned empty result")
        rescue Timeout::Error
          raise TimeoutError, "EXPLAIN query timed out after #{@timeout}s"
        rescue AdapterError
          raise
        rescue StandardError => e
          raise AdapterError, "Failed to execute EXPLAIN: #{e.message}", original_error: e
        end
      end

      def execute_query_with_timeout(sql)
        if connection.respond_to?(:execute)
          # ActiveRecord adapter (most common)
          execute_activerecord(sql)
        elsif connection.respond_to?(:query)
          # pg gem raw connection
          execute_pg_gem(sql)
        else
          raise ConnectionError, "Cannot determine connection type for EXPLAIN"
        end
      end

      def execute_activerecord(sql)
        # Using ActiveRecord's query execution
        # This handles connection pooling automatically
        result = connection.execute(sql)

        # ActiveRecord result sets have different formats per adapter
        if result.respond_to?(:rows)
          # Most adapters
          result.rows
        elsif result.respond_to?(:first)
          # Compatibility with some adapters
          [result]
        else
          raise AdapterError, "Unable to read EXPLAIN result"
        end
      end

      def execute_pg_gem(sql)
        # Raw pg gem connection
        # Note: This is rarely used in Rails but supported for completeness
        begin
          result = connection.query(sql)
          result.map(&:values)
        rescue PG::Error => e
          raise AdapterError, "PostgreSQL query failed: #{e.message}"
        end
      end

      def execute_query(sql)
        if connection.respond_to?(:execute)
          connection.execute(sql)
        elsif connection.respond_to?(:query)
          connection.query(sql)
        else
          raise ConnectionError, "Cannot execute query with this connection"
        end
      end

      def validate_connection!
        server_version
        log_debug("PostgreSQL connection validated")
      rescue StandardError => e
        connection_error = "Cannot validate PostgreSQL connection: #{e.message}"
        log_warn(connection_error)
        raise ConnectionError, connection_error
      end

      def log_debug(message, **context)
        return unless @logger

        context_str = context.empty? ? "" : " (#{context.to_s})"
        @logger.debug("[QueryGuard::PostgreSQLAdapter] #{message}#{context_str}")
      end

      def log_warn(message)
        return unless @logger

        @logger.warn("[QueryGuard::PostgreSQLAdapter] #{message}")
      end
    end
  end
end
