# frozen_string_literal: true

module QueryGuard
  module Analyzers
    # Detects SELECT * statements.
    class SelectStarAnalyzer < Base
      SELECT_STAR_PATTERN = /\bSELECT\s+\*/i.freeze

      def initialize
        super(:select_star)
      end

      def analyze(context, config)
        findings = []

        return findings unless config.block_select_star

        context.queries.each do |query|
          next unless matches_select_star?(query.sql)
          next if exceeds_ignored_sql?(query.sql, config)

          findings << Core::FindingBuilders.select_star(
            query,
            severity: config.select_star_severity || :warn
          )
        end

        findings
      end

      private

      def matches_select_star?(sql)
        SELECT_STAR_PATTERN.match?(sql)
      end

      def exceeds_ignored_sql?(sql, config)
        config.ignored_sql.any? { |pattern| pattern === sql }
      end
    end
  end
end
