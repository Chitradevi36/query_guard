# frozen_string_literal: true

module QueryGuard
  module Analyzers
    # Detects when query count per request exceeds threshold.
    class QueryCountAnalyzer < Base
      def initialize
        super(:query_count)
      end

      def analyze(context, config)
        findings = []
        limit = config.max_queries_per_request

        return findings if limit.nil?

        count = context.queries.length
        return findings unless count > limit

        findings << Core::FindingBuilders.too_many_queries(
          count: count,
          limit: limit,
          total_duration_ms: context.total_duration_ms,
          severity: config.query_count_severity || :warn
        )

        findings
      end
    end
  end
end
