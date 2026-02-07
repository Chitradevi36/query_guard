# frozen_string_literal: true

require "spec_helper"
require "query_guard/rspec"
require "query_guard"

RSpec.describe "QueryGuard RSpec matchers" do
  before do
    # Clear any thread-local stats
    Thread.current[:query_guard_stats] = nil
  end

  describe "exceed_query_budget matcher" do
    context "with inline limits" do
      it "passes when under count limit" do
        expect {
          # Simulate 3 queries
          stats = Thread.current[:query_guard_stats]
          if stats
            stats[:count] = 3
            stats[:total_duration_ms] = 100
          end
        }.to_not exceed_query_budget(count: 5)
      end

      it "fails when over count limit" do
        expect {
          stats = Thread.current[:query_guard_stats]
          if stats
            stats[:count] = 10
            stats[:total_duration_ms] = 100
          end
        }.to exceed_query_budget(count: 5)
      end

      it "passes when under duration limit" do
        expect {
          stats = Thread.current[:query_guard_stats]
          if stats
            stats[:count] = 3
            stats[:total_duration_ms] = 100
          end
        }.to_not exceed_query_budget(duration_ms: 500)
      end

      it "fails when over duration limit" do
        expect {
          stats = Thread.current[:query_guard_stats]
          if stats
            stats[:count] = 3
            stats[:total_duration_ms] = 600
          end
        }.to exceed_query_budget(duration_ms: 500)
      end

      it "checks both count and duration" do
        expect {
          stats = Thread.current[:query_guard_stats]
          if stats
            stats[:count] = 3
            stats[:total_duration_ms] = 100
          end
        }.to_not exceed_query_budget(count: 5, duration_ms: 500)
      end

      it "fails when either limit is exceeded" do
        expect {
          stats = Thread.current[:query_guard_stats]
          if stats
            stats[:count] = 10
            stats[:total_duration_ms] = 100
          end
        }.to exceed_query_budget(count: 5, duration_ms: 500)
      end
    end

    context "with named budget" do
      before do
        QueryGuard.config.budget.for("test_action", count: 5, duration_ms: 500)
      end

      it "passes when under budget" do
        expect {
          stats = Thread.current[:query_guard_stats]
          if stats
            stats[:count] = 3
            stats[:total_duration_ms] = 100
          end
        }.to_not exceed_query_budget("test_action")
      end

      it "fails when over budget" do
        expect {
          stats = Thread.current[:query_guard_stats]
          if stats
            stats[:count] = 10
            stats[:total_duration_ms] = 100
          end
        }.to exceed_query_budget("test_action")
      end

      it "raises error for undefined budget" do
        expect {
          expect {
            # code
          }.to_not exceed_query_budget("undefined_budget")
        }.to raise_error(ArgumentError, /No budget defined/)
      end
    end

    context "with negated matcher" do
      it "passes when budget is exceeded" do
        expect {
          stats = Thread.current[:query_guard_stats]
          if stats
            stats[:count] = 10
            stats[:total_duration_ms] = 100
          end
        }.to exceed_query_budget(count: 5)
      end

      it "fails when budget is not exceeded" do
        expect {
          stats = Thread.current[:query_guard_stats]
          if stats
            stats[:count] = 3
            stats[:total_duration_ms] = 100
          end
        }.to_not exceed_query_budget(count: 5)
      end
    end
  end

  describe "within_query_budget helper" do
    it "returns report when within budget" do
      report = within_query_budget(count: 10) do
        stats = Thread.current[:query_guard_stats]
        if stats
          stats[:count] = 5
          stats[:total_duration_ms] = 100
        end
      end

      expect(report).to be_a(QueryGuard::Trace::Report)
    end

    it "raises when count exceeds budget" do
      expect {
        within_query_budget(count: 5) do
          stats = Thread.current[:query_guard_stats]
          if stats
            stats[:count] = 10
            stats[:total_duration_ms] = 100
          end
        end
      }.to raise_error(QueryGuard::Budget::Violation, /Query count exceeded/)
    end

    it "raises when duration exceeds budget" do
      expect {
        within_query_budget(duration_ms: 100) do
          stats = Thread.current[:query_guard_stats]
          if stats
            stats[:count] = 5
            stats[:total_duration_ms] = 200
          end
        end
      }.to raise_error(QueryGuard::Budget::Violation, /Duration exceeded/)
    end

    it "raises with both violations" do
      expect {
        within_query_budget(count: 5, duration_ms: 100) do
          stats = Thread.current[:query_guard_stats]
          if stats
            stats[:count] = 10
            stats[:total_duration_ms] = 200
          end
        end
      }.to raise_error(QueryGuard::Budget::Violation) do |error|
        expect(error.message).to include("Query count exceeded")
        expect(error.message).to include("Duration exceeded")
      end
    end
  end
end
