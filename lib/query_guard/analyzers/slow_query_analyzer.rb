# frozen_string_literal: true

module QueryGuard
  module Analyzers
    # Detects slow queries based on duration threshold.
    class SlowQueryAnalyzer < Base
      def initialize
        super(:slow_query)
      end

      def analyze(context, config)
        findings = []
        threshold = config.max_duration_ms_per_query

        return findings if threshold.nil?

        context.queries.each do |query|
          next if exceeds_ignored_sql?(query.sql, config)
          next unless query.duration_ms > threshold

          findings << Core::FindingBuilders.slow_query(
            query,
            duration_ms: query.duration_ms,
            threshold_ms: threshold,
            severity: config.slow_query_severity || :warn
          )
        end

        findings
      end

      private

      def exceeds_ignored_sql?(sql, config)
        config.ignored_sql.any? { |pattern| pattern === sql }
      end
    end
  end
end
