# frozen_string_literal: true

module QueryGuard
  module Explain
    # Converts EXPLAIN signals into QueryGuard Finding objects.
    # Enriches existing risk findings with actual plan data and index suggestions.
    #
    # Example:
    #   adapter = PostgreSQLAdapter.new(connection)
    #   enricher = ExplainEnricher.new(adapter)
    #   findings = enricher.enrich(existing_findings, query)
    class ExplainEnricher
      def initialize(adapter, config = {})
        @adapter = adapter
        @config = config
        @logger = config[:logger]
        @index_suggester = Suggest::IndexSuggester.new
      end

      # Enrich findings with EXPLAIN analysis
      #
      # @param findings [Array<Core::Finding>] Existing findings from risk analyzers
      # @param query [Core::Query] The query to analyze
      # @param context [Core::Context, nil] Request context
      # @return [Array<Core::Finding>] Original + new findings from EXPLAIN
      def enrich(findings, query, context = nil)
        return findings if findings.nil? || query.nil?
        return findings unless can_enrich?(query)

        new_findings = []

        begin
          explain_findings = analyze_with_explain(query, context)
          new_findings.concat(explain_findings)
        rescue StandardError => e
          log_error("EXPLAIN enrichment failed: #{e.message}", query)
          # Graceful degradation: return original findings on error
        end

        findings + new_findings
      end

      # Check if this query can be enriched with EXPLAIN
      #
      # @param query [Core::Query] The query
      # @return [Boolean]
      def can_enrich?(query)
        return false if query.nil? || query.sql.nil?

        @adapter.can_explain?(query.sql)
      end

      private

      def analyze_with_explain(query, context)
        findings = []

        begin
          # Get EXPLAIN plan
          plan_json = @adapter.get_plan(query.sql)
          plan = PlanSignals::QueryPlan.new(plan_json)
          signals = PlanSignals::PlanSignals.new(plan)

          # Convert signals to findings
          signals.to_a.each do |signal|
            finding = signal_to_finding(signal, query)
            findings << finding if finding
          end

          findings
        rescue AdapterError => e
          log_error("Could not get EXPLAIN plan: #{e.message}", query)
          log_debug("Adapter error details", error: e.inspect) if @logger
          []
        rescue StandardError => e
          log_error("Unexpected error during EXPLAIN analysis: #{e.message}", query)
          []
        end
      end

      def signal_to_finding(signal, query)
        case signal[:type]
        when :sequential_scan
          create_sequential_scan_finding(signal, query)
        when :likely_missing_index
          create_missing_index_finding(signal, query)
        when :estimate_inaccuracy
          create_estimate_inaccuracy_finding(signal, query)
        when :high_estimated_cost
          create_high_cost_finding(signal, query)
        when :nested_loop_join
          create_nested_loop_finding(signal, query)
        when :high_planning_time
          create_planning_time_finding(signal, query)
        when :expensive_sort
          create_expensive_sort_finding(signal, query)
        when :bitmap_scan
          create_bitmap_scan_finding(signal, query)
        else
          nil
        end
      end

      def create_sequential_scan_finding(signal, query)
        metadata = {
          table: signal[:table],
          estimated_rows: signal[:estimated_rows],
          source: "PostgreSQL EXPLAIN",
          recommendation: signal[:recommendation]
        }

        # Add index suggestion if available
        index_suggestion = @index_suggester.suggest_for_sequential_scan(
          query.sql,
          table_name: signal[:table]
        )

        if index_suggestion
          metadata[:suggested_index_sql] = index_suggestion[:suggested_index_sql]
          metadata[:suggested_index_columns] = index_suggestion[:columns]
          metadata[:suggested_index_confidence] = index_suggestion[:confidence]
          metadata[:suggested_index_name] = index_suggestion[:index_name]
        end

        recommendations = [
          signal[:recommendation],
          "Add index on frequently filtered columns",
          "Run ANALYZE to update table statistics if stale"
        ]

        if index_suggestion
          recommendations << @index_suggester.build_recommendation_text(index_suggestion)
        end

        Core::FindingBuilders.build(
          analyzer_name: :query_risk,
          rule_name: :sequential_scan_via_explain,
          severity: :error,
          title: "Sequential Table Scan Detected",
          description: "Query uses sequential scan; table is scanned row-by-row without index",
          message: signal[:message],
          sql: query.sql,
          recommendations: recommendations,
          metadata: metadata
        )
      end

      def create_missing_index_finding(signal, query)
        metadata = {
          table: signal[:table],
          filter: signal[:filter],
          source: "PostgreSQL EXPLAIN"
        }

        # Add index suggestion if available
        index_suggestion = @index_suggester.suggest_for_sequential_scan(
          query.sql,
          table_name: signal[:table],
          filter_condition: signal[:filter]
        )

        if index_suggestion
          metadata[:suggested_index_sql] = index_suggestion[:suggested_index_sql]
          metadata[:suggested_index_columns] = index_suggestion[:columns]
          metadata[:suggested_index_confidence] = index_suggestion[:confidence]
          metadata[:suggested_index_name] = index_suggestion[:index_name]
        end

        recommendations = [
          signal[:recommendation],
          "Review index design based on query predicates"
        ]

        if index_suggestion
          recommendations << @index_suggester.build_recommendation_text(index_suggestion)
        end

        Core::FindingBuilders.build(
          analyzer_name: :query_risk,
          rule_name: :missing_index_via_explain,
          severity: :error,
          title: "Missing Index Detected",
          description: "Sequential scan with WHERE filter suggests missing index",
          message: signal[:message],
          sql: query.sql,
          recommendations: recommendations,
          metadata: metadata
        )
      end

      def create_estimate_inaccuracy_finding(signal, query)
        Core::FindingBuilders.build(
          analyzer_name: :query_risk,
          rule_name: :estimate_inaccuracy,
          severity: :warn,
          title: "Query Plan Estimate Inaccuracy",
          description: "Planner estimate differs significantly from actual execution",
          message: signal[:message],
          sql: query.sql,
          recommendations: [
            signal[:recommendation],
            "Check if table statistics are up-to-date: ANALYZE table_name",
            "Review query structure for optimization opportunities"
          ],
          metadata: {
            node: signal[:node],
            accuracy_ratio: signal[:ratio],
            source: "PostgreSQL EXPLAIN ANALYZE"
          }
        )
      end

      def create_high_cost_finding(signal, query)
        Core::FindingBuilders.build(
          analyzer_name: :query_risk,
          rule_name: :high_query_cost,
          severity: :warn,
          title: "High Query Cost Estimated",
          description: "Query planner estimates significant resource consumption",
          message: signal[:message],
          sql: query.sql,
          recommendations: [
            signal[:recommendation],
            "Consider query refactoring (JOINs, WHERE clauses, sorting)",
            "Verify indexes exist on join keys"
          ],
          metadata: {
            estimated_cost: signal[:cost],
            source: "PostgreSQL EXPLAIN"
          }
        )
      end

      def create_nested_loop_finding(signal, query)
        Core::FindingBuilders.build(
          analyzer_name: :query_risk,
          rule_name: :nested_loop_join,
          severity: :warn,
          title: "Nested Loop Join Detected",
          description: "Query uses nested loop join which may be inefficient for large datasets",
          message: signal[:message],
          sql: query.sql,
          recommendations: [
            signal[:recommendation],
            "Consider using hash join if appropriate (increase work_mem setting)",
            "Verify join condition uses indexed columns on the inner table"
          ],
          metadata: {
            inner_table: signal[:inner_table],
            source: "PostgreSQL EXPLAIN"
          }
        )
      end

      def create_planning_time_finding(signal, query)
        Core::FindingBuilders.build(
          analyzer_name: :query_risk,
          rule_name: :high_planning_time,
          severity: :info,
          title: "High Query Planning Time",
          description: "PostgreSQL planner took significant time to generate query plan",
          message: signal[:message],
          sql: query.sql,
          recommendations: [
            signal[:recommendation],
            "Review for complex JOINs or CTEs",
            "Ensure table statistics are current: ANALYZE"
          ],
          metadata: {
            planning_time_ms: signal[:planning_time_ms],
            source: "PostgreSQL EXPLAIN"
          }
        )
      end

      def create_expensive_sort_finding(signal, query)
        metadata = {
          estimated_rows: signal[:estimated_rows],
          source: "PostgreSQL EXPLAIN"
        }

        # Add index suggestion for ORDER BY clause
        # Extract table name from signal if available
        table_name = extract_table_name(query.sql)
        
        index_suggestion = nil
        if table_name
          index_suggestion = @index_suggester.suggest_for_expensive_sort(
            query.sql,
            table_name: table_name
          )

          if index_suggestion
            metadata[:suggested_index_sql] = index_suggestion[:suggested_index_sql]
            metadata[:suggested_index_columns] = index_suggestion[:columns]
            metadata[:suggested_index_confidence] = index_suggestion[:confidence]
            metadata[:suggested_index_name] = index_suggestion[:index_name]
          end
        end

        recommendations = [
          signal[:recommendation],
          "Consider index-backed ordering if possible",
          "If using pagination, only fetch needed rows"
        ]

        if index_suggestion
          recommendations << @index_suggester.build_recommendation_text(index_suggestion)
        end

        Core::FindingBuilders.build(
          analyzer_name: :query_risk,
          rule_name: :expensive_sort,
          severity: :warn,
          title: "Expensive Sort Operation",
          description: "Query performs sort on large result set which requires memory/disk I/O",
          message: signal[:message],
          sql: query.sql,
          recommendations: recommendations,
          metadata: metadata
        )
      end

      def create_bitmap_scan_finding(signal, query)
        Core::FindingBuilders.build(
          analyzer_name: :query_risk,
          rule_name: :bitmap_scan,
          severity: :info,
          title: "Bitmap Index Scan",
          description: "Query uses bitmap index scan for range queries; confirm index design",
          message: signal[:message],
          sql: query.sql,
          recommendations: [
            signal[:recommendation],
            "Bitmap scans are appropriate for range predicates with multiple OR conditions",
            "Consider composite indexes if bitmap scan isn't optimal"
          ],
          metadata: {
            table: signal[:table],
            source: "PostgreSQL EXPLAIN"
          }
        )
      end

      def log_error(message, query)
        return unless @logger

        @logger.warn("[QueryGuard::Explain] #{message} - Query: #{query.sql.strip[0..80]}")
      end

      def log_debug(message, **context)
        return unless @logger

        context_str = context.empty? ? "" : " - #{context.to_s}"
        @logger.debug("[QueryGuard::Explain] #{message}#{context_str}")
      end

      private

      def extract_table_name(sql)
        # Simple extraction of main table name from SELECT/FROM clause
        # Used for index suggestions
        Suggest::PatternExtractors.new.extract_table_name(sql)
      end
    end
  end
end