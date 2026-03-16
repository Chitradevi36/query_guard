# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Explain::PlanSignals do
  # Sample EXPLAIN outputs
  BASIC_SEQUENTIAL_SCAN = {
    "Plan" => {
      "Node Type" => "Seq Scan",
      "Relation Name" => "users",
      "Estimated Rows" => 1000,
      "Total Cost" => 35.50,
      "Filter" => "(status = 'active')"
    },
    "Planning Time" => 0.234,
    "Execution Time" => 2.543
  }.freeze

  NESTED_PLAN_STRUCTURE = {
    "Plan" => {
      "Node Type" => "Hash Join",
      "Plans" => [
        {
          "Node Type" => "Seq Scan",
          "Relation Name" => "users",
          "Estimated Rows" => 1000,
          "Total Cost" => 35.50
        },
        {
          "Node Type" => "Index Scan",
          "Relation Name" => "orders",
          "Index Name" => "idx_orders_user_id",
          "Estimated Rows" => 5000,
          "Total Cost" => 12.40
        }
      ],
      "Estimated Rows" => 5000,
      "Total Cost" => 100.00
    },
    "Planning Time" => 0.345,
    "Execution Time" => 5.234
  }.freeze

  WITH_ANALYZE = {
    "Plan" => {
      "Node Type" => "Seq Scan",
      "Relation Name" => "users",
      "Estimated Rows" => 1000,
      "Actual Rows" => 1250,
      "Total Cost" => 35.50,
      "Actual Total Time" => 15.234,
      "Filter" => "(status = 'active')"
    },
    "Planning Time" => 0.234,
    "Execution Time" => 15.234
  }.freeze

  HIGH_COST_PLAN = {
    "Plan" => {
      "Node Type" => "Nested Loop",
      "Plans" => [
        {
          "Node Type" => "Seq Scan",
          "Relation Name" => "orders",
          "Estimated Rows" => 10000,
          "Total Cost" => 5000.00
        },
        {
          "Node Type" => "Seq Scan",
          "Relation Name" => "users",
          "Estimated Rows" => 50000,
          "Total Cost" => 7500.00
        }
      ],
      "Estimated Rows" => 100000,
      "Total Cost" => 12500.00
    },
    "Planning Time" => 0.234,
    "Execution Time" => 125.543
  }.freeze

  NESTED_LOOP_PLAN = {
    "Plan" => {
      "Node Type" => "Nested Loop",
      "Plans" => [
        {
          "Node Type" => "Seq Scan",
          "Relation Name" => "users",
          "Estimated Rows" => 1000,
          "Total Cost" => 100.0
        },
        {
          "Node Type" => "Index Scan",
          "Relation Name" => "orders",
          "Index Name" => "idx_orders_user_id",
          "Estimated Rows" => 50,
          "Total Cost" => 10.0
        }
      ],
      "Estimated Rows" => 50000,
      "Total Cost" => 110.0
    },
    "Planning Time" => 0.123,
    "Execution Time" => 5.432
  }.freeze

  HIGH_PLANNING_TIME_PLAN = {
    "Plan" => {
      "Node Type" => "Seq Scan",
      "Relation Name" => "users",
      "Estimated Rows" => 100,
      "Total Cost" => 10.0
    },
    "Planning Time" => 250.543,
    "Execution Time" => 1.234
  }.freeze

  EXPENSIVE_SORT_PLAN = {
    "Plan" => {
      "Node Type" => "Sort",
      "Sort Key" => "created_at DESC",
      "Estimated Rows" => 5000,
      "Total Cost" => 5234.50,
      "Plans" => [
        {
          "Node Type" => "Seq Scan",
          "Relation Name" => "events",
          "Estimated Rows" => 5000,
          "Total Cost" => 234.50
        }
      ]
    },
    "Planning Time" => 0.123,
    "Execution Time" => 45.234
  }.freeze

  BITMAP_SCAN_PLAN = {
    "Plan" => {
      "Node Type" => "Bitmap Heap Scan",
      "Relation Name" => "products",
      "Estimated Rows" => 500,
      "Total Cost" => 125.75,
      "Plans" => [
        {
          "Node Type" => "Bitmap Index Scan",
          "Index Name" => "idx_products_range",
          "Estimated Rows" => 500,
          "Total Cost" => 25.75
        }
      ]
    },
    "Planning Time" => 0.156,
    "Execution Time" => 12.345
  }.freeze

  describe "PlanNode" do
    describe "#initialize" do
      it "extracts node attributes" do
        node = QueryGuard::Explain::PlanSignals::PlanNode.new(
          { "Node Type" => "Seq Scan", "Relation Name" => "users" }
        )

        expect(node.node_type).to eq("Seq Scan")
        expect(node.relation_name).to eq("users")
        expect(node.depth).to eq(0)
      end

      it "sets depth when provided" do
        node = QueryGuard::Explain::PlanSignals::PlanNode.new({}, 2)
        expect(node.depth).to eq(2)
      end

      it "extracts estimated metrics" do
        plan_data = {
          "Estimated Rows" => 100,
          "Total Cost" => 42.50
        }
        node = QueryGuard::Explain::PlanSignals::PlanNode.new(plan_data)

        expect(node.estimated_rows).to eq(100)
        expect(node.estimated_cost).to eq(42.50)
      end

      it "extracts actual metrics when available" do
        plan_data = {
          "Actual Rows" => 150,
          "Actual Total Time" => 2.345
        }
        node = QueryGuard::Explain::PlanSignals::PlanNode.new(plan_data)

        expect(node.actual_rows).to eq(150)
        expect(node.actual_duration_ms).to eq(2.345)
      end

      it "recursively processes child plans" do
        plan_data = {
          "Plans" => [
            { "Node Type" => "Index Scan", "Relation Name" => "users" },
            { "Node Type" => "Seq Scan", "Relation Name" => "orders" }
          ]
        }
        node = QueryGuard::Explain::PlanSignals::PlanNode.new(plan_data)

        expect(node.children).to have_length(2)
        expect(node.children[0].node_type).to eq("Index Scan")
        expect(node.children[1].node_type).to eq("Seq Scan")
      end
    end

    describe "#sequential_scan?" do
      it "identifies Seq Scan nodes" do
        node = QueryGuard::Explain::PlanSignals::PlanNode.new("Node Type" => "Seq Scan")
        expect(node.sequential_scan?).to be true
      end

      it "rejects other node types" do
        node = QueryGuard::Explain::PlanSignals::PlanNode.new("Node Type" => "Index Scan")
        expect(node.sequential_scan?).to be false
      end
    end

    describe "#index_scan?" do
      it "identifies Index Scan nodes" do
        index_types = ["Index Scan", "Index Only Scan", "Bitmap Index Scan"]
        index_types.each do |type|
          node = QueryGuard::Explain::PlanSignals::PlanNode.new("Node Type" => type)
          expect(node.index_scan?).to be true
        end
      end

      it "rejects non-index nodes" do
        node = QueryGuard::Explain::PlanSignals::PlanNode.new("Node Type" => "Seq Scan")
        expect(node.index_scan?).to be false
      end
    end

    describe "#sequential_scans" do
      it "finds sequential scans in tree" do
        plan = NESTED_PLAN_STRUCTURE["Plan"]
        node = QueryGuard::Explain::PlanSignals::PlanNode.new(plan)
        scans = node.sequential_scans

        expect(scans).to have_length(1)
        expect(scans[0].relation_name).to eq("users")
      end
    end

    describe "#estimate_accuracy_ratio" do
      it "calculates actual vs estimated ratio" do
        node = QueryGuard::Explain::PlanSignals::PlanNode.new(
          { "Estimated Rows" => 100, "Actual Rows" => 200 }
        )
        expect(node.estimate_accuracy_ratio).to eq(2.0)
      end

      it "returns nil when no actual data" do
        node = QueryGuard::Explain::PlanSignals::PlanNode.new("Estimated Rows" => 100)
        expect(node.estimate_accuracy_ratio).to be nil
      end

      it "handles zero estimated rows gracefully" do
        node = QueryGuard::Explain::PlanSignals::PlanNode.new(
          { "Estimated Rows" => 0, "Actual Rows" => 100 }
        )
        expect(node.estimate_accuracy_ratio).to be nil
      end
    end

    describe "#estimate_inaccurate?" do
      it "detects large overestimates" do
        node = QueryGuard::Explain::PlanSignals::PlanNode.new(
          { "Estimated Rows" => 100, "Actual Rows" => 1500 }
        )
        expect(node.estimate_inaccurate?).to be true
      end

      it "detects large underestimates" do
        node = QueryGuard::Explain::PlanSignals::PlanNode.new(
          { "Estimated Rows" => 1000, "Actual Rows" => 50 }
        )
        expect(node.estimate_inaccurate?).to be true
      end

      it "accepts small deviations" do
        node = QueryGuard::Explain::PlanSignals::PlanNode.new(
          { "Estimated Rows" => 100, "Actual Rows" => 110 }
        )
        expect(node.estimate_inaccurate?).to be false
      end

      it "returns false without actual data" do
        node = QueryGuard::Explain::PlanSignals::PlanNode.new("Estimated Rows" => 100)
        expect(node.estimate_inaccurate?).to be false
      end
    end
  end

  describe "QueryPlan" do
    let(:plan) { QueryGuard::Explain::PlanSignals::QueryPlan.new(BASIC_SEQUENTIAL_SCAN) }

    describe "#initialize" do
      it "extracts timing metrics" do
        expect(plan.planning_time_ms).to eq(0.234)
        expect(plan.execution_time_ms).to eq(2.543)
      end

      it "creates root node from plan data" do
        expect(plan.root_node).to be_a(QueryGuard::Explain::PlanSignals::PlanNode)
        expect(plan.root_node.node_type).to eq("Seq Scan")
      end
    end

    describe "#sequential_scans" do
      it "finds all sequential scans" do
        nested_plan = QueryGuard::Explain::PlanSignals::QueryPlan.new(NESTED_PLAN_STRUCTURE)
        scans = nested_plan.sequential_scans

        expect(scans).to have_length(1)
        expect(scans[0].relation_name).to eq("users")
      end
    end

    describe "#uses_indexes?" do
      it "returns true when indexes are used" do
        nested_plan = QueryGuard::Explain::PlanSignals::QueryPlan.new(NESTED_PLAN_STRUCTURE)
        expect(nested_plan.uses_indexes?).to be true
      end

      it "returns false for sequential scans only" do
        seq_plan = QueryGuard::Explain::PlanSignals::QueryPlan.new(BASIC_SEQUENTIAL_SCAN)
        expect(seq_plan.uses_indexes?).to be false
      end
    end

    describe "#total_estimated_cost" do
      it "returns root node cost" do
        expect(plan.total_estimated_cost).to eq(35.50)
      end

      it "sums nested plan costs" do
        nested_plan = QueryGuard::Explain::PlanSignals::QueryPlan.new(NESTED_PLAN_STRUCTURE)
        expect(nested_plan.total_estimated_cost).to eq(100.00)
      end
    end
  end

  describe "PlanSignals" do
    describe "sequential scan detection" do
      let(:signals) { QueryGuard::Explain::PlanSignals::PlanSignals.new(
        QueryGuard::Explain::PlanSignals::QueryPlan.new(BASIC_SEQUENTIAL_SCAN)
      ) }

      it "extracts sequential scan signal" do
        seq_signals = signals.signals_of_type(:sequential_scan)
        expect(seq_signals).to have_length(1)
        expect(seq_signals[0][:severity]).to eq(:high)
      end

      it "includes table name in signal" do
        seq_signals = signals.signals_of_type(:sequential_scan)
        expect(seq_signals[0][:table]).to eq("users")
      end
    end

    describe "estimate inaccuracy detection" do
      let(:signals) { QueryGuard::Explain::PlanSignals::PlanSignals.new(
        QueryGuard::Explain::PlanSignals::QueryPlan.new(WITH_ANALYZE)
      ) }

      it "detects inaccurate estimates" do
        inaccuracy_signals = signals.signals_of_type(:estimate_inaccuracy)
        expect(inaccuracy_signals.length).to be > 0
      end
    end

    describe "high cost detection" do
      let(:signals) { QueryGuard::Explain::PlanSignals::PlanSignals.new(
        QueryGuard::Explain::PlanSignals::QueryPlan.new(HIGH_COST_PLAN)
      ) }

      it "detects high estimated costs" do
        cost_signals = signals.signals_of_type(:high_estimated_cost)
        expect(cost_signals).to have_length(1)
        expect(cost_signals[0][:severity]).to eq(:medium)
      end

      it "includes cost value in signal" do
        cost_signals = signals.signals_of_type(:high_estimated_cost)
        expect(cost_signals[0][:cost]).to eq(12500.00)
      end
    end

    describe "#signals_of_type" do
      let(:signals) { QueryGuard::Explain::PlanSignals::PlanSignals.new(
        QueryGuard::Explain::PlanSignals::QueryPlan.new(BASIC_SEQUENTIAL_SCAN)
      ) }

      it "filters signals by type" do
        seq_signals = signals.signals_of_type(:sequential_scan)
        expect(seq_signals.all? { |s| s[:type] == :sequential_scan }).to be true
      end

      it "returns empty array for non-existent type" do
        fake_signals = signals.signals_of_type(:fake_type)
        expect(fake_signals).to be_empty
      end
    end

    describe "#critical_signals" do
      let(:signals) { QueryGuard::Explain::PlanSignals::PlanSignals.new(
        QueryGuard::Explain::PlanSignals::QueryPlan.new(HIGH_COST_PLAN)
      ) }

      it "filters by severity" do
        high_severity = signals.critical_signals(:high)
        expect(high_severity.all? { |s| s[:severity] == :high }).to be true
      end
    end

    describe "nested loop join detection" do
      let(:signals) { QueryGuard::Explain::PlanSignals::PlanSignals.new(
        QueryGuard::Explain::PlanSignals::QueryPlan.new(NESTED_LOOP_PLAN)
      ) }

      it "detects nested loop joins" do
        loop_signals = signals.signals_of_type(:nested_loop_join)
        expect(loop_signals).to have_length(1)
      end

      it "includes inner table in nested loop signal" do
        loop_signals = signals.signals_of_type(:nested_loop_join)
        expect(loop_signals[0][:inner_table]).to eq("orders")
      end

      it "sets appropriate severity" do
        loop_signals = signals.signals_of_type(:nested_loop_join)
        expect(loop_signals[0][:severity]).to eq(:medium)
      end
    end

    describe "high planning time detection" do
      let(:signals) { QueryGuard::Explain::PlanSignals::PlanSignals.new(
        QueryGuard::Explain::PlanSignals::QueryPlan.new(HIGH_PLANNING_TIME_PLAN)
      ) }

      it "detects high planning time" do
        time_signals = signals.signals_of_type(:high_planning_time)
        expect(time_signals).to have_length(1)
      end

      it "includes planning time in milliseconds" do
        time_signals = signals.signals_of_type(:high_planning_time)
        expect(time_signals[0][:planning_time_ms]).to eq(250.543)
      end

      it "sets low severity for planning time" do
        time_signals = signals.signals_of_type(:high_planning_time)
        expect(time_signals[0][:severity]).to eq(:low)
      end
    end

    describe "expensive sort detection" do
      let(:signals) { QueryGuard::Explain::PlanSignals::PlanSignals.new(
        QueryGuard::Explain::PlanSignals::QueryPlan.new(EXPENSIVE_SORT_PLAN)
      ) }

      it "detects expensive sorts on large results" do
        sort_signals = signals.signals_of_type(:expensive_sort)
        expect(sort_signals).to have_length(1)
      end

      it "includes estimated rows in signal" do
        sort_signals = signals.signals_of_type(:expensive_sort)
        expect(sort_signals[0][:estimated_rows]).to eq(5000)
      end

      it "sets appropriate severity" do
        sort_signals = signals.signals_of_type(:expensive_sort)
        expect(sort_signals[0][:severity]).to eq(:medium)
      end
    end

    describe "bitmap scan detection" do
      let(:signals) { QueryGuard::Explain::PlanSignals::PlanSignals.new(
        QueryGuard::Explain::PlanSignals::QueryPlan.new(BITMAP_SCAN_PLAN)
      ) }

      it "detects bitmap scans" do
        bitmap_signals = signals.signals_of_type(:bitmap_scan)
        expect(bitmap_signals).to have_length(1)
      end

      it "includes table name in bitmap signal" do
        bitmap_signals = signals.signals_of_type(:bitmap_scan)
        expect(bitmap_signals[0][:table]).to eq("products")
      end

      it "sets low severity for bitmap scans (generally acceptable)" do
        bitmap_signals = signals.signals_of_type(:bitmap_scan)
        expect(bitmap_signals[0][:severity]).to eq(:low)
      end
    end
  end
end
