# frozen_string_literal: true

module QueryGuard
  module Suggest
    # Generates index suggestions for queries with missing index indicators.
    # Conservative approach: only suggests when patterns match common cases.
    # All suggestions include disclaimer that they're recommendations only.
    #
    # Example:
    #   suggester = IndexSuggester.new
    #   suggestion = suggester.suggest_for_sequential_scan(
    #     "SELECT * FROM users WHERE email = 'test@example.com'",
    #     table_name: "users"
    #   )
    #   # => {
    #   #   suggested_index_sql: "CREATE INDEX idx_users_email ON users (email);",
    #   #   explanation: "Index on email column for WHERE clause equality",
    #   #   confidence: :medium,
    #   #   columns: ["email"]
    #   # }
    class IndexSuggester
      CONFIDENCE_LEVELS = %i[high medium low].freeze

      def initialize
        @extractors = PatternExtractors.new
      end

      # Generate index suggestion for sequential scan with filter
      #
      # @param sql [String] SQL query
      # @param table_name [String] Table being scanned
      # @param filter_condition [String] WHERE clause filter (optional)
      # @return [Hash, nil] Suggestion hash or nil if no reasonable suggestion
      def suggest_for_sequential_scan(sql, table_name:, filter_condition: nil)
        return nil if sql.nil? || table_name.nil?

        # Extract columns from WHERE clause
        where_cols = @extractors.extract_where_columns(sql)
        return nil if where_cols.empty?

        # Use first column as primary index candidate
        # This is conservative: most benefit comes from first filter
        primary_col = where_cols.first
        suggest_index(table_name, primary_col, high_confidence: true)
      end

      # Generate index suggestion for expensive sort
      #
      # @param sql [String] SQL query
      # @param table_name [String] Table being sorted
      # @return [Hash, nil] Suggestion hash or nil
      def suggest_for_expensive_sort(sql, table_name:)
        return nil if sql.nil? || table_name.nil?

        # Extract ORDER BY columns
        order_cols = @extractors.extract_order_by_columns(sql)
        return nil if order_cols.empty?

        # For sorts, index all ORDER BY columns in order
        suggest_composite_index(table_name, order_cols, reason: "sort")
      end

      # Generate index suggestion for multi-column filter
      # For WHERE with multiple equality conditions, suggest composite
      #
      # @param sql [String] SQL query
      # @param table_name [String] Table being filtered
      # @return [Hash, nil] Suggestion hash or nil
      def suggest_for_complex_filter(sql, table_name:)
        return nil if sql.nil? || table_name.nil?

        where_cols = @extractors.extract_where_columns(sql)
        return nil if where_cols.length < 2

        # Conservative: only suggest composite for 2-3 columns
        return nil if where_cols.length > 3

        suggest_composite_index(table_name, where_cols, reason: "composite filter")
      end

      # Generate index suggestion for JOIN condition
      # Suggests index on join key in inner table
      #
      # @param column_name [String] Join column name
      # @param table_name [String] Inner table name
      # @return [Hash] Suggestion hash
      def suggest_for_join(column_name, table_name:)
        return nil if column_name.nil? || table_name.nil?

        suggest_index(table_name, column_name, high_confidence: true, reason: "join condition")
      end

      # Build neutral recommendation text for a suggestion
      #
      # @param suggestion [Hash] Suggestion from suggest_* methods
      # @return [String] User-facing recommendation text
      def build_recommendation_text(suggestion)
        return nil unless suggestion

        text = suggestion[:explanation]
        text += " (confidence: #{suggestion[:confidence]})"
        text += "\n\nIMPORTANT: This is a recommendation based on query pattern analysis. "
        text += "Before creating the index:\n"
        text += "  1. Verify this index hasn't already been suggested elsewhere\n"
        text += "  2. Check index size impact and maintenance cost\n"
        text += "  3. Run EXPLAIN ANALYZE with and without the index\n"
        text += "  4. Consider selectivity of indexed columns\n"
        text += "  5. Test in development first\n\n"
        text += "Suggested SQL (REVIEW BEFORE RUNNING):\n#{suggestion[:suggested_index_sql]}"
        text
      end

      private

      def suggest_index(table_name, column_name, high_confidence: false, reason: nil)
        col_safe = sanitize_identifier(column_name)
        table_safe = sanitize_identifier(table_name)
        index_name = "idx_#{table_safe}_#{col_safe}".downcase

        {
          suggested_index_sql: "CREATE INDEX #{index_name} ON #{table_safe} (#{col_safe});",
          explanation: build_explanation(reason || "column filter", [column_name]),
          confidence: high_confidence ? :high : :medium,
          columns: [column_name],
          index_name: index_name,
          table_name: table_name
        }
      end

      def suggest_composite_index(table_name, column_names, reason: nil)
        return nil if column_names.empty?

        # Conservative: don't suggest composite for too many columns
        return nil if column_names.length > 4

        table_safe = sanitize_identifier(table_name)
        cols_safe = column_names.map { |c| sanitize_identifier(c) }
        col_list = cols_safe.join(", ")
        
        # Index name: idx_table_col1_col2
        index_name = "idx_#{table_safe}_#{cols_safe.join('_')}".downcase[0...63] # 63 char limit

        {
          suggested_index_sql: "CREATE INDEX #{index_name} ON #{table_safe} (#{col_list});",
          explanation: build_explanation(reason || "composite filter", column_names),
          confidence: :medium,
          columns: column_names,
          index_name: index_name,
          table_name: table_name
        }
      end

      def build_explanation(reason, columns)
        col_str = columns.length == 1 ? "#{columns[0]} column" : "#{columns.join(', ')} columns"
        case reason
        when "sort"
          "Index on #{col_str} for ORDER BY clause"
        when "composite filter"
          "Composite index on #{col_str} for WHERE clause"
        when "join condition"
          "Index on #{col_str} for JOIN condition"
        else
          "Index on #{col_str} for #{reason}"
        end
      end

      def sanitize_identifier(identifier)
        # Basic sanitization: allow alphanumeric and underscore
        # PostgreSQL identifiers: letters, digits, underscores
        sanitized = identifier.to_s.downcase.gsub(/[^a-z0-9_]/, '_')
        # Remove leading digits (invalid)
        sanitized.gsub(/^[0-9]+/, '')
      end
    end
  end
end
