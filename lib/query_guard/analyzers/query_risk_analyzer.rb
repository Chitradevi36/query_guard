# frozen_string_literal: true

module QueryGuard
  module Analyzers
    # Analyzes queries for performance and safety risks.
    # Evaluates SQL patterns, missing indexes, N+1 patterns, and other risks.
    # Optionally enriches findings with EXPLAIN plan analysis (PostgreSQL).
    class QueryRiskAnalyzer < Base
      def initialize
        super(:query_risk)
      end

      def analyze(context, config)
        findings = []
        # Only analyze if enabled
        return findings unless config.analyze_query_risks

        classifier = Analysis::QueryRiskClassifier.new(config)

        # Analyze each query individually
        context.queries.each do |query|
          risks = classifier.analyze_query(query)
          query_findings = risks_to_findings(risks, query, config)

          # Enrich with EXPLAIN analysis if enabled
          if config.use_explain_plans && config.explain_enricher
            query_findings = config.explain_enricher.enrich(query_findings, query, context)
          end

          findings.concat(query_findings)
        end

        # Analyze request-level patterns (N+1, repeated queries)
        context_risks = classifier.analyze_context_risks(context)
        findings.concat(context_risks_to_findings(context_risks, config))

        findings
      end

      private

      def risks_to_findings(risks, query, config)
        findings = []

        risks.each do |risk|
          severity = Analysis::RiskLevel.to_severity(risk[:risk_level])

          finding = Core::FindingBuilders.build(
            analyzer_name: name,
            rule_name: risk[:pattern],
            severity: severity,
            title: risk_title(risk[:pattern]),
            description: risk_description(risk[:pattern]),
            message: risk[:message],
            sql: query.sql,
            metadata: risk[:metadata],
            recommendations: [risk[:metadata][:recommendation]],
            query: query
          )

          findings << finding
        end

        findings
      end

      def context_risks_to_findings(risks, config)
        findings = []

        risks.each do |risk|
          severity = Analysis::RiskLevel.to_severity(risk[:risk_level])

          finding = Core::FindingBuilders.build(
            analyzer_name: name,
            rule_name: risk[:pattern],
            severity: severity,
            title: risk_title(risk[:pattern]),
            description: risk_description(risk[:pattern]),
            message: risk[:message],
            metadata: risk[:metadata],
            recommendations: [risk[:metadata][:recommendation]]
          )

          findings << finding
        end

        findings
      end

      def risk_title(pattern)
        case pattern
        when :select_star
          "SELECT * Usage"
        when :like_without_index
          "LIKE Without Index"
        when :function_in_join
          "Function in JOIN Condition"
        when :many_joins
          "Complex Multi-Table Join"
        when :nested_subqueries
          "Nested Subqueries"
        when :union_query
          "UNION Query"
        when :distinct_usage
          "DISTINCT Clause"
        when :group_by_unordered
          "GROUP BY Without ORDER BY"
        when :repeated_query
          "Repeated Query in Request"
        when :potential_n_plus_one
          "Potential N+1 Query Problem"
        else
          pattern.to_s.titleize
        end
      end

      def risk_description(pattern)
        case pattern
        when :select_star
          "Selecting all columns can fetch unnecessary data and reduce efficiency."
        when :like_without_index
          "LIKE pattern matching typically requires full table scans."
        when :function_in_join
          "Functions in JOIN conditions prevent index usage."
        when :many_joins
          "Queries joining many tables are complex and difficult to optimize."
        when :nested_subqueries
          "Nested subqueries can cause multiple table scans."
        when :union_query
          "UNION requires sorting; UNION ALL is often faster."
        when :distinct_usage
          "DISTINCT forces sorting and can be expensive."
        when :group_by_unordered
          "GROUP BY without ORDER BY returns results in unpredictable order."
        when :repeated_query
          "Same query executed multiple times suggests missing eager loading."
        when :potential_n_plus_one
          "Many sequential queries in a single request indicates an N+1 problem."
        else
          pattern.to_s.titleize
        end
      end
    end
  end
end

