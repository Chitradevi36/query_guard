# frozen_string_literal: true

module QueryGuard
  module Suggest
    # Extracts SQL patterns from queries for index suggestion.
    # Conservative patterns only - only suggests when reasonably confident.
    #
    # Example:
    #   extractor = PatternExtractors.new
    #   where_cols = extractor.extract_where_columns("SELECT * FROM users WHERE email = 'test@example.com'")
    #   # => ["email"]
    #
    #   order_cols = extractor.extract_order_by_columns("SELECT * FROM events ORDER BY created_at DESC")
    #   # => ["created_at"]
    class PatternExtractors
      # Extract column names from WHERE clause
      # Handles: simple equality, comparison operators
      # Avoids: functions, expressions, BETWEEN
      #
      # @param sql [String] SQL query
      # @return [Array<String>] Column names in WHERE clause
      def extract_where_columns(sql)
        return [] if sql.nil? || sql.empty?

        normalized = normalize_sql(sql)
        where_match = normalized.match(/\bWHERE\s+(.+?)(?:\s+(?:GROUP|ORDER|LIMIT|HAVING)(?:\s|$)|$)/i)
        return [] unless where_match

        where_clause = where_match[1]
        extract_columns_from_where(where_clause)
      end

      # Extract column names from ORDER BY clause
      # Handles: simple column ordering
      # Avoids: expressions, COLLATE, NULLS FIRST/LAST
      #
      # @param sql [String] SQL query
      # @return [Array<String>] Column names in ORDER BY clause
      def extract_order_by_columns(sql)
        return [] if sql.nil? || sql.empty?

        normalized = normalize_sql(sql)
        order_match = normalized.match(/\bORDER\s+BY\s+(.+?)(?:\s+(?:LIMIT)(?:\s|$)|$)/i)
        return [] unless order_match

        order_clause = order_match[1]
        extract_columns_from_order_by(order_clause)
      end

      # Extract both WHERE and ORDER BY columns
      # Returns them in a structured format for index suggestion
      #
      # @param sql [String] SQL query
      # @return [Hash] { where_columns: [...], order_by_columns: [...] }
      def extract_all_columns(sql)
        {
          where_columns: extract_where_columns(sql),
          order_by_columns: extract_order_by_columns(sql)
        }
      end

      # Extract table name from query
      # Simple extraction of first table mentioned after FROM
      #
      # @param sql [String] SQL query
      # @return [String, nil] Table name
      def extract_table_name(sql)
        return nil if sql.nil? || sql.empty?

        normalized = normalize_sql(sql)
        # Match FROM or JOIN followed by table name
        # Handles: "FROM users", "FROM public.users", "JOIN orders ON"
        match = normalized.match(/\b(?:FROM|JOIN)\s+(?:(?:\w+\.)?(\w+))\b/i)
        match&.[](1)&.downcase
      end

      private

      def normalize_sql(sql)
        # Remove comments and extra whitespace
        sql
          .gsub(/--.*$/, '')           # Remove line comments
          .gsub(/\/\*.*?\*\//m, '')    # Remove block comments
          .gsub(/\s+/, ' ')            # Collapse whitespace
          .strip
      end

      def extract_columns_from_where(where_clause)
        columns = []

        # Match simple patterns: column = value, column > value, column IN (...)
        # Skip function calls and complex expressions
        where_clause.scan(/\b(\w+)\s*(?:=|<>|!=|>|<|>=|<=|LIKE|IN)/i) do |match|
          col = match[0].downcase
          # Skip obvious non-column keywords
          next if skip_keyword?(col)

          columns << col unless columns.include?(col)
        end

        columns
      end

      def extract_columns_from_order_by(order_clause)
        columns = []

        # Match column names before ASC/DESC/comma
        # Pattern: word (optionally preceded by table name)
        order_clause.split(',').each do |part|
          # Remove ASC/DESC modifiers
          cleaned = part.gsub(/\s+(?:ASC|DESC)\s*$/i, '').strip

          # Extract column name (handle schema.table.column references)
          col_match = cleaned.match(/\b(\w+)\s*$/)
          next unless col_match

          col = col_match[1].downcase
          next if skip_keyword?(col)

          columns << col unless columns.include?(col)
        end

        columns
      end

      def skip_keyword?(word)
        # Skip SQL keywords and common aliases
        keywords = %w[
          and or not null true false case when then else end 
          select insert update delete from where join on group having order by limit offset
          asc desc ignore using force straight_join key
        ]
        keywords.include?(word.downcase)
      end
    end
  end
end
