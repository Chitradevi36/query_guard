# frozen_string_literal: true

module QueryGuard
  module Core
    # Factory builders for common finding types.
    # Provides convenient methods to create well-structured findings
    # without manually specifying all parameters.
    #
    # Example:
    #   finding = FindingBuilders.slow_query(
    #     query,
    #     duration_ms: 250.5,
    #     threshold_ms: 100.0
    #   )
    module FindingBuilders
      # Slow query finding
      def self.slow_query(query, duration_ms:, threshold_ms:, **opts)
        Finding.new(
          analyzer_name: :slow_query,
          rule_name: :duration_exceeded,
          severity: opts[:severity] || :warn,
          title: "Slow Query Detected",
          description: "Query execution time exceeded the configured threshold.",
          message: "Query took #{duration_ms.round(2)}ms (limit: #{threshold_ms}ms)",
          sql: query&.sql,
          metadata: {
            duration_ms: duration_ms,
            threshold_ms: threshold_ms
          },
          recommendations: [
            "Add indexes on frequently queried columns",
            "Review and optimize the query logic",
            "Consider using pagination for large result sets",
            "Check database statistics"
          ],
          query: query,
          file_path: opts[:file_path],
          line_number: opts[:line_number]
        )
      end

      # Too many queries finding
      def self.too_many_queries(count:, limit:, total_duration_ms:, **opts)
        Finding.new(
          analyzer_name: :query_count,
          rule_name: :count_exceeded,
          severity: opts[:severity] || :warn,
          title: "Too Many Queries",
          description: "Request executed more queries than the configured limit.",
          message: "Executed #{count} queries (limit: #{limit})",
          metadata: {
            count: count,
            limit: limit,
            total_duration_ms: total_duration_ms
          },
          recommendations: [
            "Use eager loading (N+1 query prevention)",
            "Consolidate multiple queries into one",
            "Use database-level aggregations where possible",
            "Consider caching results"
          ],
          file_path: opts[:file_path],
          line_number: opts[:line_number]
        )
      end

      # SELECT * finding
      def self.select_star(query, **opts)
        Finding.new(
          analyzer_name: :select_star,
          rule_name: :select_star_detected,
          severity: opts[:severity] || :warn,
          title: "SELECT * Used",
          description: "Query uses SELECT * instead of specifying columns.",
          message: "SELECT * detected in query",
          sql: query&.sql,
          metadata: {
            sql: query&.sql
          },
          recommendations: [
            "Specify only required columns explicitly",
            "Reduces bandwidth and improves query efficiency",
            "Makes schema changes less error-prone",
            "Enables better query optimization by the database"
          ],
          query: query,
          file_path: opts[:file_path],
          line_number: opts[:line_number]
        )
      end

      # Generic builder for custom findings
      def self.build(analyzer_name:, rule_name:, **opts)
        Finding.new(
          analyzer_name: analyzer_name,
          rule_name: rule_name,
          severity: opts[:severity] || :warn,
          title: opts[:title],
          description: opts[:description],
          message: opts[:message],
          sql: opts[:sql],
          metadata: opts[:metadata] || {},
          recommendations: opts[:recommendations] || [],
          query: opts[:query],
          file_path: opts[:file_path],
          line_number: opts[:line_number]
        )
      end

      # Migration-related finding (prepared for Phase 2)
      def self.migration_risk(migration_file:, issue:, **opts)
        Finding.new(
          analyzer_name: :migration_safety,
          rule_name: opts[:rule_name] || :unsafe_operation,
          severity: opts[:severity] || :error,
          title: opts[:title] || "Migration Risk Detected",
          description: opts[:description] || "Migration may cause data loss or downtime.",
          message: issue,
          file_path: migration_file,
          line_number: opts[:line_number],
          metadata: opts[:metadata] || {},
          recommendations: opts[:recommendations] || [
            "Review migration carefully before deploying",
            "Test on a staging environment",
            "Consider phased rollout for large tables"
          ]
        )
      end

      # Pattern matching finding (prepared for future analyzers)
      def self.pattern_detected(query, pattern_type:, **opts)
        Finding.new(
          analyzer_name: opts[:analyzer_name] || :pattern_detector,
          rule_name: opts[:rule_name] || :pattern_detected,
          severity: opts[:severity] || :info,
          title: opts[:title] || "Pattern Detected",
          description: opts[:description] || "A query pattern was detected.",
          message: opts[:message] || "#{pattern_type} pattern detected",
          sql: query&.sql,
          metadata: {
            pattern_type: pattern_type,
            **(opts[:metadata] || {})
          },
          recommendations: opts[:recommendations] || [],
          query: query,
          file_path: opts[:file_path],
          line_number: opts[:line_number]
        )
      end
    end
  end
end
