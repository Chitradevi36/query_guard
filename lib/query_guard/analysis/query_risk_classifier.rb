# frozen_string_literal: true

module QueryGuard
  module Analysis
    # Query risk classifier and aggregator.
    # Orchestrates all risk detectors and produces findings.
    class QueryRiskClassifier
      def initialize(config)
        @config = config
        @detectors = [
          SelectStarRiskDetector.new,
          MissingIndexRiskDetector.new,
          ComplexJoinRiskDetector.new,
          SubqueryRiskDetector.new,
          UnionRiskDetector.new,
          AggregationRiskDetector.new
        ]
      end

      # Analyze a single query for risks
      # @param query [Core::Query]
      # @return [Array<Hash>] Detected risks
      def analyze_query(query)
        risks = []
        @detectors.each do |detector|
          risks.concat(detector.detect(query, @config))
        end
        risks
      end

      # Analyze all queries in context for request-level risks (N+1, repeated queries)
      # @param context [Core::Context]
      # @return [Array<Hash>] Request-level risks
      def analyze_context_risks(context)
        risks = []

        # Detect potentially repeated queries (same SQL pattern)
        risks.concat(detect_repeated_queries(context))

        # Detect potential N+1 pattern: many queries in sequence
        risks.concat(detect_n_plus_one_pattern(context))

        risks
      end

      private

      def detect_repeated_queries(context)
        risks = []
        return risks if context.queries.length < 2

        # Group queries by normalized SQL
        query_groups = context.queries.group_by { |q| normalize_sql(q.sql) }

        # Find SQL patterns executed multiple times
        query_groups.each do |_normalized_sql, queries|
          next if queries.length < 3

          risks << {
            pattern: :repeated_query,
            risk_level: :medium,
            message: "Query executed #{queries.length} times in single request; possible N+1 or missing eager load",
            metadata: {
              count: queries.length,
              duration_total_ms: queries.sum(&:duration_ms),
              recommendation: "Use eager loading (e.g., .includes) or batch queries",
              impact: "Unnecessary query overhead"
            }
          }
        end

        risks
      end

      def detect_n_plus_one_pattern(context)
        risks = []
        return risks if context.queries.length < 5

        # Simple heuristic: many SELECT FROM single table queries in sequence
        select_queries = context.queries.select { |q| q.sql.match?(/^SELECT\b/i) }
        return risks if select_queries.length < 5

        # Heuristic: similar query patterns (likely same table)
        patterns = select_queries.map { |q| extract_table_name(q.sql) }.compact.uniq
        return risks if patterns.length < 2

        # If we have many queries (5+) hitting few tables, likely N+1
        select_count = select_queries.length
        if select_count >= 5
          avg_duration = context.total_duration_ms / context.queries.length
          risks << {
            pattern: :potential_n_plus_one,
            risk_level: :high,
            message: "Detected #{select_count} SELECT queries hitting ~#{patterns.length} table(s); likely N+1 query problem",
            metadata: {
              select_count: select_count,
              table_count: patterns.length,
              avg_query_ms: avg_duration.round(2),
              recommendation: "Use eager loading (.includes, .joins) or batch queries",
              impact: "Performance degradation with data scale"
            }
          }
        end

        risks
      end

      def normalize_sql(sql)
        sql.upcase.gsub(/\d+/, "?").gsub(/\s+/, " ").strip
      end

      def extract_table_name(sql)
        # Simple heuristic: first table after FROM
        if sql.match?(/\bFROM\s+(\w+)/i)
          sql.match(/\bFROM\s+(\w+)/i)[1].downcase
        elsif sql.match?(/\bINTO\s+(\w+)/i)
          sql.match(/\bINTO\s+(\w+)/i)[1].downcase
        else
          nil
        end
      end
    end
  end
end
