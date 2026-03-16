# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Explain::ExplainEnricher do
  let(:mock_adapter) { MockExplainAdapter.new }
  let(:enricher) { described_class.new(mock_adapter) }

  # Mock adapter for testing
  class MockExplainAdapter
    def initialize
      @can_explain_result = true
      @plan_result = default_sequential_scan_plan
    end

    def can_explain?(sql)
      @can_explain_result
    end

    def get_plan(sql)
      @plan_result
    end

    def set_can_explain(value)
      @can_explain_result = value
    end

    def set_plan_result(plan)
      @plan_result = plan
    end

    private

    def default_sequential_scan_plan
      {
        "Plan" => {
          "Node Type" => "Seq Scan",
          "Relation Name" => "users",
          "Estimated Rows" => 1000,
          "Total Cost" => 35.50,
          "Filter" => "(status = 'active')"
        },
        "Planning Time" => 0.234,
        "Execution Time" => 2.543
      }
    end
  end

  def create_query(sql, name = "test_query")
    QueryGuard::Core::Query.new(sql: sql, name: name, duration_ms: 10)
  end

  def create_finding(sql = "SELECT * FROM users")
    QueryGuard::Core::FindingBuilders.build(
      analyzer_name: :test,
      rule_name: :test_rule,
      sql: sql
    )
  end

  describe "#initialize" do
    it "stores adapter" do
      expect(enricher.instance_variable_get(:@adapter)).to eq(mock_adapter)
    end

    it "accepts optional config" do
      config_enricher = described_class.new(mock_adapter, logger: :some_logger)
      expect(config_enricher.instance_variable_get(:@logger)).to eq(:some_logger)
    end
  end

  describe "#can_enrich?" do
    it "returns true for enrichable queries" do
      query = create_query("SELECT * FROM users WHERE status = 'active'")
      expect(enricher.can_enrich?(query)).to be true
    end

    it "returns false when adapter cannot explain" do
      mock_adapter.set_can_explain(false)
      query = create_query("SELECT * FROM users")
      expect(enricher.can_enrich?(query)).to be false
    end

    it "returns false for nil query" do
      expect(enricher.can_enrich?(nil)).to be false
    end

    it "returns false for query with nil sql" do
      query = create_query(nil)
      expect(enricher.can_enrich?(query)).to be false
    end
  end

  describe "#enrich" do
    context "with enrichable queries" do
      it "adds findings from EXPLAIN analysis" do
        original_findings = [create_finding]
        query = create_query("SELECT * FROM users WHERE status = 'active'")

        new_findings = enricher.enrich(original_findings, query)

        expect(new_findings.length).to be > original_findings.length
      end

      it "preserves original findings" do
        original = [create_finding]
        query = create_query("SELECT * FROM users WHERE status = 'active'")

        result = enricher.enrich(original, query)

        expect(result).to include(original[0])
      end

      it "detects sequential scans" do
        original_findings = []
        query = create_query("SELECT * FROM users WHERE status = 'active'")

        new_findings = enricher.enrich(original_findings, query)

        sequential_scan_findings = new_findings.select { |f| f.rule_name == :sequential_scan_via_explain }
        expect(sequential_scan_findings).not_to be_empty
      end

      it "includes sequential scan table name" do
        query = create_query("SELECT * FROM users WHERE status = 'active'")
        new_findings = enricher.enrich([], query)

        seq_findings = new_findings.select { |f| f.rule_name == :sequential_scan_via_explain }
        expect(seq_findings[0].metadata[:table]).to eq("users")
      end

      it "sets error severity for sequential scans" do
        query = create_query("SELECT * FROM users")
        new_findings = enricher.enrich([], query)

        seq_findings = new_findings.select { |f| f.rule_name == :sequential_scan_via_explain }
        expect(seq_findings[0].severity).to eq(:error)
      end

      it "creates findings with sql included" do
        sql = "SELECT * FROM users WHERE id = 1"
        query = create_query(sql)
        new_findings = enricher.enrich([], query)

        expect(new_findings[0].sql).to eq(sql)
      end

      it "includes recommendations in findings" do
        query = create_query("SELECT * FROM users")
        new_findings = enricher.enrich([], query)

        expect(new_findings[0].recommendations).not_to be_empty
        expect(new_findings[0].recommendations[0]).to be_a(String)
      end
    end

    context "with non-enrichable queries" do
      it "returns original findings unchanged" do
        mock_adapter.set_can_explain(false)
        original = [create_finding]
        query = create_query("SELECT * FROM users")

        result = enricher.enrich(original, query)

        expect(result).to eq(original)
      end

      it "gracefully handles nil findings" do
        query = create_query("SELECT * FROM users")
        result = enricher.enrich(nil, query)

        expect(result).to be_nil
      end

      it "gracefully handles error during EXPLAIN" do
        mock_adapter.define_singleton_method(:get_plan) do |_sql|
          raise QueryGuard::Explain::AdapterError, "Connection failed"
        end

        original = [create_finding]
        query = create_query("SELECT * FROM users")

        # Should not raise, should log and return original
        result = enricher.enrich(original, query)

        expect(result).to eq(original)
      end
    end

    context "with different EXPLAIN scenarios" do
      it "detects missing indexes" do
        plan = {
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Relation Name" => "orders",
            "Filter" => "(user_id = 123)",
            "Estimated Rows" => 5000,
            "Total Cost" => 150.00
          },
          "Planning Time" => 0.1,
          "Execution Time" => 5.0
        }

        mock_adapter.set_plan_result(plan)
        query = create_query("SELECT * FROM orders WHERE user_id = 123")

        new_findings = enricher.enrich([], query)
        missing_index = new_findings.find { |f| f.rule_name == :missing_index_via_explain }

        expect(missing_index).not_to be_nil
        expect(missing_index.title).to eq("Missing Index Detected")
      end

      it "detects high query costs" do
        plan = {
          "Plan" => {
            "Node Type" => "Nested Loop",
            "Estimated Rows" => 100000,
            "Total Cost" => 20000.00,
            "Plans" => [
              { "Node Type" => "Seq Scan", "Relation Name" => "a", "Total Cost" => 10000.00 },
              { "Node Type" => "Seq Scan", "Relation Name" => "b", "Total Cost" => 10000.00 }
            ]
          },
          "Planning Time" => 0.5,
          "Execution Time" => 50.0
        }

        mock_adapter.set_plan_result(plan)
        query = create_query("SELECT * FROM a JOIN b ON a.id = b.a_id")

        new_findings = enricher.enrich([], query)
        cost_findings = new_findings.select { |f| f.rule_name == :high_query_cost }

        expect(cost_findings).not_to be_empty
      end
    end
  end

  describe "signal_to_finding conversion" do
    it "converts sequential_scan signal to finding" do
      query = create_query("SELECT * FROM users")
      signal = {
        type: :sequential_scan,
        severity: :high,
        table: "users",
        estimated_rows: 1000,
        message: "Sequential scan on users",
        recommendation: "Add index"
      }

      finding = enricher.send(:signal_to_finding, signal, query)

      expect(finding.rule_name).to eq(:sequential_scan_via_explain)
      expect(finding.severity).to eq(:error)
      expect(finding.title).to eq("Sequential Table Scan Detected")
    end

    it "converts missing_index signal to finding" do
      query = create_query("SELECT * FROM users WHERE email = 'test@example.com'")
      signal = {
        type: :likely_missing_index,
        severity: :high,
        table: "users",
        filter: "(email = 'test@example.com')",
        message: "Sequential scan with filter",
        recommendation: "Analyze columns"
      }

      finding = enricher.send(:signal_to_finding, signal, query)

      expect(finding.rule_name).to eq(:missing_index_via_explain)
      expect(finding.title).to eq("Missing Index Detected")
    end

    it "converts estimate_inaccuracy signal to finding" do
      query = create_query("SELECT * FROM users")
      signal = {
        type: :estimate_inaccuracy,
        severity: :medium,
        node: "Seq Scan",
        ratio: 15.5,
        message: "Estimate off by 1550%",
        recommendation: "Run ANALYZE"
      }

      finding = enricher.send(:signal_to_finding, signal, query)

      expect(finding.rule_name).to eq(:estimate_inaccuracy)
      expect(finding.severity).to eq(:warn)
      expect(finding.metadata[:accuracy_ratio]).to eq(15.5)
    end

    it "converts high_estimated_cost signal to finding" do
      query = create_query("SELECT * FROM users JOIN orders")
      signal = {
        type: :high_estimated_cost,
        severity: :medium,
        cost: 15000.0,
        message: "High estimated cost",
        recommendation: "Review query"
      }

      finding = enricher.send(:signal_to_finding, signal, query)

      expect(finding.rule_name).to eq(:high_query_cost)
      expect(finding.metadata[:estimated_cost]).to eq(15000.0)
    end

    it "returns nil for unknown signal types" do
      query = create_query("SELECT * FROM users")
      signal = { type: :unknown_type }

      finding = enricher.send(:signal_to_finding, signal, query)

      expect(finding).to be_nil
    end

    describe "nested loop join signal conversion" do
      it "converts nested_loop_join signal to finding" do
        query = create_query("SELECT * FROM users JOIN orders ON users.id = orders.user_id")
        signal = {
          type: :nested_loop_join,
          severity: :medium,
          message: "Nested loop join detected with orders",
          recommendation: "Consider adding indexes",
          inner_table: "orders"
        }

        finding = enricher.send(:signal_to_finding, signal, query)

        expect(finding.rule_name).to eq(:nested_loop_join)
        expect(finding.severity).to eq(:warn)
        expect(finding.title).to eq("Nested Loop Join Detected")
        expect(finding.metadata[:inner_table]).to eq("orders")
      end
    end

    describe "high planning time signal conversion" do
      it "converts high_planning_time signal to finding" do
        query = create_query("SELECT * FROM users")
        signal = {
          type: :high_planning_time,
          severity: :low,
          planning_time_ms: 150.5,
          message: "High planning time: 150.5ms",
          recommendation: "Check for complex joins"
        }

        finding = enricher.send(:signal_to_finding, signal, query)

        expect(finding.rule_name).to eq(:high_planning_time)
        expect(finding.severity).to eq(:info)
        expect(finding.title).to eq("High Query Planning Time")
        expect(finding.metadata[:planning_time_ms]).to eq(150.5)
      end
    end

    describe "expensive sort signal conversion" do
      it "converts expensive_sort signal to finding" do
        query = create_query("SELECT * FROM events ORDER BY created_at DESC")
        signal = {
          type: :expensive_sort,
          severity: :medium,
          estimated_rows: 10000,
          message: "Sorting 10000 rows",
          recommendation: "Use pagination"
        }

        finding = enricher.send(:signal_to_finding, signal, query)

        expect(finding.rule_name).to eq(:expensive_sort)
        expect(finding.severity).to eq(:warn)
        expect(finding.title).to eq("Expensive Sort Operation")
        expect(finding.metadata[:estimated_rows]).to eq(10000)
      end
    end

    describe "bitmap scan signal conversion" do
      it "converts bitmap_scan signal to finding" do
        query = create_query("SELECT * FROM products WHERE price BETWEEN 10 AND 100")
        signal = {
          type: :bitmap_scan,
          severity: :low,
          table: "products",
          message: "Bitmap index scan on products",
          recommendation: "Verify index design"
        }

        finding = enricher.send(:signal_to_finding, signal, query)

        expect(finding.rule_name).to eq(:bitmap_scan)
        expect(finding.severity).to eq(:info)
        expect(finding.title).to eq("Bitmap Index Scan")
        expect(finding.metadata[:table]).to eq("products")
      end
    end
  end

  describe "error handling" do
    context "when adapter raises AdapterError" do
      it "logs error and returns original findings" do
        mock_adapter.define_singleton_method(:get_plan) do |_sql|
          raise QueryGuard::Explain::AdapterError, "Connection timeout"
        end

        original = [create_finding]
        query = create_query("SELECT * FROM users")
        logger_mock = instance_double(Logger)
        enricher_with_logger = described_class.new(mock_adapter, logger: logger_mock)

        expect(logger_mock).to receive(:warn).at_least(:once)

        result = enricher_with_logger.enrich(original, query)
        expect(result).to eq(original)
      end
    end

    context "when adapter raises TimeoutError" do
      it "gracefully degradates" do
        mock_adapter.define_singleton_method(:get_plan) do |_sql|
          raise QueryGuard::Explain::TimeoutError, "EXPLAIN timed out"
        end

        query = create_query("SELECT * FROM huge_table")

        result = enricher.enrich([], query)
        expect(result).to eq([])
      end
    end

    context "when unexpected error occurs" do
      it "logs and returns empty findings" do
        mock_adapter.define_singleton_method(:get_plan) do |_sql|
          raise StandardError, "Unexpected error"
        end

        query = create_query("SELECT * FROM users")
        logger_mock = instance_double(Logger)
        enricher_with_logger = described_class.new(mock_adapter, logger: logger_mock)

        expect(logger_mock).to receive(:warn).at_least(:once)

        result = enricher_with_logger.enrich([], query)
        expect(result).to eq([])
      end
    end
  end
end
