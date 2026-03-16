# frozen_string_literal: true

require "spec_helper"
require "query_guard/trace"
require "query_guard/config"
require "query_guard"

RSpec.describe QueryGuard::Trace do
  describe ".trace" do
    it "returns result and report tuple" do
      result, report = described_class.trace("test") do
        "test result"
      end

      expect(result).to eq("test result")
      expect(report).to be_a(QueryGuard::Trace::Report)
    end

    it "captures label" do
      _, report = described_class.trace("test label") { nil }

      expect(report.label).to eq("test label")
    end

    it "captures context" do
      context = { user_id: 123, batch: "abc" }
      _, report = described_class.trace("test", context: context) { nil }

      expect(report.context).to eq(context)
    end

    it "initializes stats tracking" do
      _, report = described_class.trace("test") { nil }

      expect(report.query_count).to eq(0)
      expect(report.total_duration_ms).to eq(0)
    end

    it "tracks queries within the block" do
      _, report = described_class.trace("test") do
        # Simulate query tracking
        stats = Thread.current[:query_guard_stats]
        stats[:count] = 3
        stats[:total_duration_ms] = 150.5
        stats[:queries] = [
          { sql: "SELECT * FROM users", duration_ms: 50 },
          { sql: "SELECT * FROM posts", duration_ms: 100.5 }
        ]
      end

      expect(report.query_count).to eq(3)
      expect(report.total_duration_ms).to eq(150.5)
      expect(report.queries.length).to eq(2)
    end

    it "captures violations" do
      _, report = described_class.trace("test") do
        stats = Thread.current[:query_guard_stats]
        stats[:violations] << { type: :slow_query, sql: "SELECT * FROM users", duration_ms: 500 }
      end

      expect(report.has_violations?).to be true
      expect(report.violations.length).to eq(1)
      expect(report.violations[0][:type]).to eq(:slow_query)
    end

    it "restores previous stats after execution" do
      previous_stats = { test: "previous" }
      Thread.current[:query_guard_stats] = previous_stats

      described_class.trace("test") { nil }

      expect(Thread.current[:query_guard_stats]).to eq(previous_stats)
    end

    it "restores previous stats even on exception" do
      previous_stats = { test: "previous" }
      Thread.current[:query_guard_stats] = previous_stats

      expect {
        described_class.trace("test") { raise "error" }
      }.to raise_error("error")

      expect(Thread.current[:query_guard_stats]).to eq(previous_stats)
    end

    context "with budget configured" do
      let(:config) do
        c = QueryGuard::Config.new
        c.budget.for("budget test", count: 5)
        c
      end

      before do
        allow(QueryGuard).to receive(:config).and_return(config)
      end

      it "checks budget violations" do
        _, report = described_class.trace("budget test") do
          stats = Thread.current[:query_guard_stats]
          stats[:count] = 10 # Exceeds budget of 5
        end

        expect(report.has_violations?).to be true
        budget_violation = report.violations.find { |v| v[:type] == :budget_exceeded_count }
        expect(budget_violation).not_to be_nil
      end

      it "does not add violations when under budget" do
        _, report = described_class.trace("budget test") do
          stats = Thread.current[:query_guard_stats]
          stats[:count] = 3 # Under budget of 5
        end

        expect(report.has_violations?).to be false
      end
    end
  end

  describe "QueryGuard.trace" do
    it "delegates to Trace.trace" do
      result, report = QueryGuard.trace("test") do
        "result"
      end

      expect(result).to eq("result")
      expect(report).to be_a(QueryGuard::Trace::Report)
    end

    it "passes context through" do
      context = { test: "value" }
      _, report = QueryGuard.trace("test", context: context) { nil }

      expect(report.context).to eq(context)
    end
  end

  describe QueryGuard::Trace::Report do
    let(:stats) do
      {
        count: 5,
        total_duration_ms: 250.5,
        queries: [
          { sql: "SELECT * FROM users", duration_ms: 100 },
          { sql: "SELECT * FROM posts", duration_ms: 150.5 }
        ],
        fingerprints: { "abc123" => 3, "def456" => 2 }
      }
    end

    let(:violations) do
      [{ type: :slow_query, sql: "SELECT * FROM users", duration_ms: 500 }]
    end

    let(:report) do
      described_class.new("test label", { user: 123 }, stats, violations)
    end

    describe "#query_count" do
      it "returns the query count" do
        expect(report.query_count).to eq(5)
      end
    end

    describe "#total_duration_ms" do
      it "returns the total duration" do
        expect(report.total_duration_ms).to eq(250.5)
      end
    end

    describe "#queries" do
      it "returns the queries array" do
        expect(report.queries.length).to eq(2)
        expect(report.queries[0][:sql]).to eq("SELECT * FROM users")
      end
    end

    describe "#fingerprints" do
      it "returns the fingerprints hash" do
        expect(report.fingerprints).to eq({ "abc123" => 3, "def456" => 2 })
      end
    end

    describe "#has_violations?" do
      it "returns true when violations exist" do
        expect(report.has_violations?).to be true
      end

      it "returns false when no violations" do
        no_violations_report = described_class.new("test", {}, stats, [])
        expect(no_violations_report.has_violations?).to be false
      end
    end

    describe "#to_h" do
      it "returns a hash representation" do
        hash = report.to_h

        expect(hash[:label]).to eq("test label")
        expect(hash[:context]).to eq({ user: 123 })
        expect(hash[:query_count]).to eq(5)
        expect(hash[:total_duration_ms]).to eq(250.5)
        expect(hash[:violations]).to eq(violations)
      end
    end
  end
end
