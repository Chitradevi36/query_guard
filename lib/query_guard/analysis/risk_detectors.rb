# frozen_string_literal: true

module QueryGuard
  module Analysis
    # Base class for query risk detectors.
    # Detectors analyze specific SQL patterns and return risks.
    class RiskDetector
      attr_reader :name

      def initialize(name)
        @name = name.to_sym
      end

      # Analyze a query and return risks
      # @param query [Core::Query] The query to analyze
      # @param config [Config] Configuration with thresholds
      # @return [Array<Hash>] List of detected risks with :pattern, :risk_level, :message, :metadata
      def detect(query, config)
        raise NotImplementedError, "#{self.class} must implement #detect"
      end

      protected

      # Extract SQL normalized (uppercase, whitespace normalized)
      def normalize_sql(sql)
        sql.upcase.gsub(/\s+/, " ").strip
      end

      # Check if pattern matches (case-insensitive regex)
      def matches_pattern?(sql, pattern)
        pattern.match?(sql)
      end
    end

    # Detects SELECT * usage patterns
    class SelectStarRiskDetector < RiskDetector
      SELECT_STAR_PATTERN = /\bSELECT\s+\*/i.freeze

      def initialize
        super(:select_star_risk)
      end

      def detect(query, config)
        risks = []
        return risks unless matches_pattern?(query.sql, SELECT_STAR_PATTERN)

        risks << {
          pattern: :select_star,
          risk_level: :medium,
          message: "SELECT * can fetch unnecessary columns, increasing bandwidth and reducing query efficiency",
          metadata: {
            recommendation: "Specify only required columns explicitly",
            impact: "Unnecessary data transfer; harder schema evolution"
          }
        }

        risks
      end
    end

    # Detects missing table alias patterns (likely missing indexes)
    class MissingIndexRiskDetector < RiskDetector
      # Patterns that often indicate missing indexes
      FULL_TABLE_SCAN_INDICATORS = [
        /\bWHERE\b.*\b(?:LIKE|ILIKE|REGEXP)\b/i,  # LIKE on non-indexed column
        /\bON\b.*\b(?:FUNCTION|CAST|COALESCE)\b/i  # Function in JOIN condition
      ].freeze

      def initialize
        super(:missing_index_risk)
      end

      def detect(query, config)
        risks = []
        sql = query.sql

        # Simple heuristic: LIKE without index hint
        if matches_pattern?(sql, FULL_TABLE_SCAN_INDICATORS[0])
          risks << {
            pattern: :like_without_index,
            risk_level: :high,
            message: "LIKE pattern matching often requires full table scan; consider full-text search or indexed prefix matching",
            metadata: {
              recommendation: "Index column(s) or use full-text search",
              impact: "Sequential scan on large tables"
            }
          }
        end

        # Function in JOIN condition
        if matches_pattern?(sql, FULL_TABLE_SCAN_INDICATORS[1])
          risks << {
            pattern: :function_in_join,
            risk_level: :high,
            message: "Functions in JOIN conditions prevent index usage, causing sequential scans",
            metadata: {
              recommendation: "Move function outside JOIN condition",
              impact: "Index cannot be used"
            }
          }
        end

        risks
      end
    end

    # Detects patterns indicative of N+1 or repeated queries
    class RepeatedQueryRiskDetector < RiskDetector
      def initialize
        super(:repeated_query_risk)
      end

      # Note: Can only detect within current request context
      def detect(query, config)
        risks = []
        # Detected at request level by QueryRiskAnalyzer
        # Return empty for now; actual detection happens in orchestrator
        risks
      end
    end

    # Detects complex join patterns
    class ComplexJoinRiskDetector < RiskDetector
      # 5+ tables is generally considered complex
      COMPLEX_JOIN_TABLE_COUNT = 5

      def initialize
        super(:complex_join_risk)
      end

      def detect(query, config)
        risks = []
        sql = query.sql

        # Count JOIN keywords (crude heuristic)
        join_count = sql.scan(/\bJOIN\b/i).length
        return risks if join_count < COMPLEX_JOIN_TABLE_COUNT

        risks << {
          pattern: :many_joins,
          risk_level: :medium,
          message: "Query with #{join_count + 1} tables; complex joins can be slow and hard to optimize",
          metadata: {
            table_count: join_count + 1,
            recommendation: "Consider breaking into multiple queries or database view",
            impact: "Performance degradation with scale"
          }
        }

        risks
      end
    end

    # Detects subquery patterns
    class SubqueryRiskDetector < RiskDetector
      SUBQUERY_PATTERN = /\(SELECT\b/i.freeze

      def initialize
        super(:subquery_risk)
      end

      def detect(query, config)
        risks = []
        return risks unless matches_pattern?(query.sql, SUBQUERY_PATTERN)

        # Count subqueries
        subquery_count = query.sql.scan(/\(SELECT\b/i).length
        return risks if subquery_count.zero?

        # Nested subqueries are more risky
        risk_level = subquery_count > 2 ? :high : :medium

        risks << {
          pattern: :nested_subqueries,
          risk_level: risk_level,
          message: "Query contains #{subquery_count} subquery(ies); consider using JOINs or CTE for better performance",
          metadata: {
            subquery_count: subquery_count,
            recommendation: "Replace with JOIN or WITH clause",
            impact: "Multiple table scans"
          }
        }

        risks
      end
    end

    # Detects UNION queries (can be slower than OR)
    class UnionRiskDetector < RiskDetector
      UNION_PATTERN = /\bUNION\b/i.freeze

      def initialize
        super(:union_risk)
      end

      def detect(query, config)
        risks = []
        return risks unless matches_pattern?(query.sql, UNION_PATTERN)

        # UNION ALL is better than UNION (no sorting)
        has_union_all = query.sql.match?(/\bUNION\s+ALL\b/i)

        risks << {
          pattern: :union_query,
          risk_level: has_union_all ? :low : :medium,
          message: "UNION #{'ALL' if has_union_all} query; consider OR clause or application-level merging",
          metadata: {
            has_union_all: has_union_all,
            recommendation: has_union_all ? "Consider OR instead" : "Use UNION ALL instead of UNION",
            impact: "Sorting overhead if UNION (not ALL)"
          }
        }

        risks
      end
    end

    # Detects GROUP BY / DISTINCT patterns
    class AggregationRiskDetector < RiskDetector
      def initialize
        super(:aggregation_risk)
      end

      def detect(query, config)
        risks = []
        sql = query.sql

        # DISTINCT on large columns
        if query.sql.match?(/\bSELECT\s+DISTINCT\b/i)
          risks << {
            pattern: :distinct_usage,
            risk_level: :low,
            message: "DISTINCT forces sorting; ensure needed and indexed properly",
            metadata: {
              recommendation: "Verify uniqueness constraint or consider GROUP BY",
              impact: "Sorting overhead"
            }
          }
        end

        # GROUP BY without ORDER BY (random order)
        if sql.match?(/\bGROUP\s+BY\b/i) && !sql.match?(/\bORDER\s+BY\b/i)
          risks << {
            pattern: :group_by_unordered,
            risk_level: :low,
            message: "GROUP BY without ORDER BY returns results in random order; add ORDER BY if order matters",
            metadata: {
              recommendation: "Add ORDER BY if result order is important",
              impact: "Unpredictable result ordering"
            }
          }
        end

        risks
      end
    end
  end
end
