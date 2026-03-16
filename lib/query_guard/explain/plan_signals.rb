# frozen_string_literal: true

module QueryGuard
  module Explain
    # Data structures for query plan signals extracted from EXPLAIN output.
    # These immutable objects represent actionable insights from actual query plans.

    # Represents a single node in the query plan tree
    class PlanNode
      attr_reader :node_type, :relation_name, :depth, :estimated_rows,
                  :estimated_cost, :actual_rows, :actual_duration_ms,
                  :children, :filter, :index_name, :sort_key

      def initialize(data, depth = 0)
        @raw_data = data
        @node_type = data.dig("Node Type") || "Unknown"  # Seq Scan, Index Scan, etc.
        @relation_name = data.dig("Relation Name")       # users, orders, etc.
        @index_name = data.dig("Index Name")             # idx_users_email, etc.
        @depth = depth

        # Estimated metrics (from planner)
        @estimated_rows = data.dig("Estimated Rows") || 0
        @estimated_cost = data.dig("Total Cost") || 0.0

        # Actual metrics (only with ANALYZE)
        @actual_rows = data.dig("Actual Rows")
        @actual_duration_ms = data.dig("Actual Total Time")

        # Plan details
        @filter = data.dig("Filter")                      # WHERE condition
        @sort_key = data.dig("Sort Key")                  # ORDER BY clause

        # Recursively process child plans
        child_plans = data.dig("Plans") || []
        @children = child_plans.map { |child| PlanNode.new(child, depth + 1) }
      end

      # Check if this node performs a sequential scan
      #
      # @return [Boolean]
      def sequential_scan?
        node_type == "Seq Scan"
      end

      # Check if this node uses an index
      #
      # @return [Boolean]
      def index_scan?
        node_type.include?("Index")
      end

      # Find all sequential scans in plan tree
      #
      # @return [Array<PlanNode>]
      def sequential_scans
        scans = sequential_scan? ? [self] : []
        children.each { |child| scans.concat(child.sequential_scans) }
        scans
      end

      # Find all nodes of given type
      #
      # @param type [String] Node type to search for
      # @return [Array<PlanNode>]
      def nodes_of_type(type)
        nodes = node_type == type ? [self] : []
        children.each { |child| nodes.concat(child.nodes_of_type(type)) }
        nodes
      end

      # Estimate quality: ratio of actual vs estimated rows
      # Returns nil if no actual execution data
      #
      # @return [Float, nil] Actual rows / Estimated rows (or nil)
      def estimate_accuracy_ratio
        return nil if actual_rows.nil? || estimated_rows.zero?

        (actual_rows.to_f / estimated_rows).round(2)
      end

      # Check if estimates were wildly inaccurate
      #
      # @param threshold [Float] How many times off is "bad"? (default 10x)
      # @return [Boolean]
      def estimate_inaccurate?(threshold = 10)
        ratio = estimate_accuracy_ratio
        return false if ratio.nil?

        ratio > threshold || ratio < (1.0 / threshold)
      end

      # Human-readable node description
      #
      # @return [String]
      def to_s
        parts = [node_type]
        parts << "on #{relation_name}" if relation_name
        parts << "using #{index_name}" if index_name
        parts.join(" ")
      end

      # Convert to hash for serialization
      #
      # @return [Hash]
      def to_h
        {
          node_type: node_type,
          relation_name: relation_name,
          index_name: index_name,
          depth: depth,
          estimated_rows: estimated_rows,
          estimated_cost: estimated_cost,
          actual_rows: actual_rows,
          actual_duration_ms: actual_duration_ms,
          is_sequential_scan: sequential_scan?,
          is_index_scan: index_scan?,
          estimate_friendly: estimate_accuracy_ratio,
          children: children.map(&:to_h)
        }
      end
    end

    # Complete query plan and extracted signals
    class QueryPlan
      attr_reader :root_node, :planning_time_ms, :execution_time_ms, :triggers

      def initialize(explain_output)
        @raw_output = explain_output

        # Top-level metrics
        @planning_time_ms = explain_output.dig("Planning Time") || 0
        @execution_time_ms = explain_output.dig("Execution Time") || 0
        @triggers = explain_output.dig("Triggers") || []

        # Root plan node
        @root_node = PlanNode.new(explain_output.dig("Plan") || {})
      end

      # Extract all sequential scans from entire plan tree
      #
      # @return [Array<PlanNode>]
      def sequential_scans
        root_node.sequential_scans
      end

      # Find specific relation scans
      #
      # @param table_name [String] Table to find scans for
      # @return [Array<PlanNode>]
      def scans_for_table(table_name)
        root_node.nodes_of_type("Seq Scan")
          .select { |node| node.relation_name == table_name }
      end

      # Check if plan uses any indexes
      #
      # @return [Boolean]
      def uses_indexes?
        root_node.nodes_of_type("Index Scan").any? ||
          root_node.nodes_of_type("Bitmap Index Scan").any? ||
          root_node.nodes_of_type("Index Only Scan").any?
      end

      # Total estimated cost of query
      #
      # @return [Float]
      def total_estimated_cost
        root_node.estimated_cost
      end

      # Convert to hash for serialization
      #
      # @return [Hash]
      def to_h
        {
          planning_time_ms: planning_time_ms,
          execution_time_ms: execution_time_ms,
          total_estimated_cost: total_estimated_cost,
          has_sequential_scans: sequential_scans.any?,
          sequential_scan_count: sequential_scans.length,
          uses_indexes: uses_indexes?,
          root_node: root_node.to_h
        }
      end
    end

    # Actionable signals extracted from query plan
    class PlanSignals
      attr_reader :plan, :signals, :extracted_at

      def initialize(plan)
        @plan = plan
        @extracted_at = Time.now
        @signals = extract_signals
      end

      # All extracted signals as array
      #
      # @return [Array<Hash>]
      def to_a
        signals
      end

      # Find signals of specific type
      #
      # @param type [String] Signal type
      # @return [Array<Hash>]
      def signals_of_type(type)
        signals.select { |s| s[:type] == type }
      end

      # Get most critical signals
      #
      # @param severity [Symbol] :high, :medium, :low
      # @return [Array<Hash>]
      def critical_signals(severity = :high)
        signals.select { |s| s[:severity] == severity }
      end

      # Convert to hash for serialization
      #
      # @return [Hash]
      def to_h
        {
          plan: plan.to_h,
          signals: signals,
          extracted_at: extracted_at
        }
      end

      private

      def extract_signals
        signals = []

        # Signal: Sequential scans on large tables
        sequential_scans.each do |scan|
          signals << {
            type: :sequential_scan,
            severity: :high,
            table: scan.relation_name,
            estimated_rows: scan.estimated_rows,
            message: "Sequential scan on #{scan.relation_name} (#{scan.estimated_rows} estimated rows)",
            recommendation: "Consider adding an index to support query predicates"
          }
        end

        # Signal: Missing indexes (likely)
        plan.root_node.nodes_of_type("Seq Scan").each do |scan|
          if scan.filter && !plan.scans_for_table(scan.relation_name).any? { |s| s.index_scan? }
            signals << {
              type: :likely_missing_index,
              severity: :high,
              table: scan.relation_name,
              filter: scan.filter,
              message: "Sequential scan with filter on #{scan.relation_name}",
              recommendation: "Analyze columns in filter condition for index opportunities"
            }
          end
        end

        # Signal: Inaccurate estimate
        walk_plan(plan.root_node).each do |node|
          if node.estimate_inaccurate?
            ratio = node.estimate_accuracy_ratio
            signals << {
              type: :estimate_inaccuracy,
              severity: :medium,
              node: node.to_s,
              ratio: ratio,
              message: "Estimate off by #{(ratio * 100).to_i}% (estimated: #{node.estimated_rows}, actual: #{node.actual_rows})",
              recommendation: "Consider running ANALYZE on table statistics"
            }
          end
        end

        # Signal: High cost query
        if plan.total_estimated_cost > 10000
          signals << {
            type: :high_estimated_cost,
            severity: :medium,
            cost: plan.total_estimated_cost,
            message: "Query has high estimated cost: #{plan.total_estimated_cost.round(2)}",
            recommendation: "Review query structure and indexes"
          }
        end

        # Signal: Nested loop joins (potential N+1 equivalent)
        walk_plan(plan.root_node).each do |node|
          if nested_loop_join?(node)
            inner_relation = find_inner_scan(node)
            signals << {
              type: :nested_loop_join,
              severity: :medium,
              message: "Nested loop join detected#{inner_relation ? " with #{inner_relation}" : ""}",
              recommendation: "Consider adding indexes on inner table join columns or using hash join with increased work_mem",
              inner_table: inner_relation
            }
          end
        end

        # Signal: High planning time (possible to_sql overhead or complex stats)
        if plan.planning_time_ms > 100
          signals << {
            type: :high_planning_time,
            severity: :low,
            planning_time_ms: plan.planning_time_ms,
            message: "High planning time: #{plan.planning_time_ms.round(2)}ms",
            recommendation: "Query planner took significant time; check for complex joins, CTEs, or stale statistics"
          }
        end

        # Signal: Sort operations on large result sets
        walk_plan(plan.root_node).each do |node|
          if node.sort_key && node.estimated_rows > 1000
            signals << {
              type: :expensive_sort,
              severity: :medium,
              estimated_rows: node.estimated_rows,
              message: "Sorting large result set (#{node.estimated_rows} estimated rows) on #{node.sort_key}",
              recommendation: "Verify sort is necessary; consider index-backed ordering or pagination"
            }
          end
        end

        # Signal: Bitmap scans (generally less efficient than proper indexes)
        walk_plan(plan.root_node).each do |node|
          if bitmap_scan?(node)
            signals << {
              type: :bitmap_scan,
              severity: :low,
              table: node.relation_name,
              message: "Bitmap index scan on #{node.relation_name}",
              recommendation: "Confirm index choice is appropriate; may indicate need for composite index"
            }
          end
        end

        signals
      end

      def sequential_scans
        plan.sequential_scans
      end

      def walk_plan(node)
        nodes = [node]
        node.children.each { |child| nodes.concat(walk_plan(child)) }
        nodes
      end

      # Check if node is a nested loop join
      #
      # @param node [PlanNode] Node to check
      # @return [Boolean]
      def nested_loop_join?(node)
        node.node_type == "Nested Loop"
      end

      # Check if node is a bitmap scan
      #
      # @param node [PlanNode] Node to check
      # @return [Boolean]
      def bitmap_scan?(node)
        node.node_type.include?("Bitmap")
      end

      # Find inner scan node in nested loop (typically the rightmost scan)
      #
      # @param node [PlanNode] Nested loop node
      # @return [String, nil] Table name of inner scan
      def find_inner_scan(node)
        return nil if node.children.empty?

        # The last child is typically the inner scan
        inner_child = node.children.last
        # Traverse to find the actual table scan
        scan_node = walk_plan(inner_child).find do |n|
          n.sequential_scan? || n.index_scan?
        end
        scan_node&.relation_name
      end
    end
  end
end
