# frozen_string_literal: true

module QueryGuard
  module Core
    # Holds the state of a single request or analysis session.
    # Replaces implicit Thread.current usage for better testability and clarity.
    class Context
      attr_reader :queries, :findings

      def initialize
        @queries = []
        @findings = []
      end

      # Add a captured query to the context
      def add_query(sql:, duration_ms:, name: nil, started_at: nil, finished_at: nil)
        query = Query.new(
          sql: sql,
          duration_ms: duration_ms,
          name: name,
          started_at: started_at,
          finished_at: finished_at
        )
        @queries << query
        query
      end

      # Add a finding to the context
      def add_finding(finding)
        raise ArgumentError, "Must be a Finding" unless finding.is_a?(Finding)
        @findings << finding
      end

      # Convenience: create and add a finding
      def create_finding(analyzer_name:, rule_name:, severity: :warn, message:, metadata: {}, query: nil)
        finding = Finding.new(
          analyzer_name: analyzer_name,
          rule_name: rule_name,
          severity: severity,
          message: message,
          metadata: metadata,
          query: query
        )
        add_finding(finding)
        finding
      end

      # Query counts for easy checking
      def query_count
        @queries.length
      end

      def total_duration_ms
        @queries.sum { |q| q.duration_ms }
      end

      # Finding counts
      def finding_count
        @findings.length
      end

      def findings_by_severity(severity)
        @findings.select { |f| f.severity == severity.to_sym }
      end

      def clear
        @queries.clear
        @findings.clear
      end

      def to_h
        {
          query_count: query_count,
          total_duration_ms: total_duration_ms,
          findings: findings.map(&:to_h)
        }
      end
    end
  end
end
