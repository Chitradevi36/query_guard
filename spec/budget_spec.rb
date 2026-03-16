# frozen_string_literal: true

require "spec_helper"
require "query_guard/budget"

RSpec.describe QueryGuard::Budget do
  let(:budget) { described_class.new }

  describe "#for" do
    it "defines a budget for controller#action" do
      budget.for("users#index", count: 10, duration_ms: 500)
      
      rule = budget.budget_for("users#index")
      expect(rule).to eq(count: 10, duration_ms: 500)
    end

    it "normalizes keys" do
      budget.for("Users#Index", count: 10)
      
      expect(budget.budget_for("users#index")).to eq(count: 10)
      expect(budget.budget_for("Users#Index")).to eq(count: 10)
    end

    it "merges multiple calls for same key" do
      budget.for("posts#show", count: 5)
      budget.for("posts#show", duration_ms: 300)
      
      rule = budget.budget_for("posts#show")
      expect(rule).to eq(count: 5, duration_ms: 300)
    end
  end

  describe "#for_job" do
    it "defines a budget for a job class name" do
      budget.for_job("EmailJob", count: 50, duration_ms: 2000)
      
      rule = budget.budget_for("job:EmailJob")
      expect(rule).to eq(count: 50, duration_ms: 2000)
    end

    it "accepts a class object" do
      email_job_class = Class.new { def self.to_s; "EmailJob"; end }
      budget.for_job(email_job_class, count: 50)
      
      expect(budget.budget_for("job:EmailJob")).to eq(count: 50)
    end
  end

  describe "#mode=" do
    it "accepts valid modes" do
      [:log, :notify, :raise].each do |mode|
        expect { budget.mode = mode }.not_to raise_error
        expect(budget.mode).to eq(mode)
      end
    end

    it "rejects invalid modes" do
      expect { budget.mode = :invalid }.to raise_error(ArgumentError, /Invalid mode/)
    end
  end

  describe "#on_violation=" do
    it "accepts a callable" do
      callback = ->(key, violation) { }
      expect { budget.on_violation = callback }.not_to raise_error
      expect(budget.on_violation).to eq(callback)
    end

    it "rejects non-callable" do
      expect { budget.on_violation = "not callable" }.to raise_error(ArgumentError, /must be callable/)
    end
  end

  describe "#check" do
    before do
      budget.for("users#index", count: 10, duration_ms: 500)
    end

    it "returns empty array when under budget" do
      stats = { count: 5, total_duration_ms: 300 }
      violations = budget.check("users#index", stats)
      
      expect(violations).to be_empty
    end

    it "detects count violation" do
      stats = { count: 15, total_duration_ms: 300 }
      violations = budget.check("users#index", stats)
      
      expect(violations.length).to eq(1)
      expect(violations[0][:type]).to eq(:budget_exceeded_count)
      expect(violations[0][:actual]).to eq(15)
      expect(violations[0][:limit]).to eq(10)
    end

    it "detects duration violation" do
      stats = { count: 5, total_duration_ms: 600 }
      violations = budget.check("users#index", stats)
      
      expect(violations.length).to eq(1)
      expect(violations[0][:type]).to eq(:budget_exceeded_duration)
      expect(violations[0][:actual]).to eq(600)
      expect(violations[0][:limit]).to eq(500)
    end

    it "detects multiple violations" do
      stats = { count: 15, total_duration_ms: 600 }
      violations = budget.check("users#index", stats)
      
      expect(violations.length).to eq(2)
      expect(violations.map { |v| v[:type] }).to contain_exactly(
        :budget_exceeded_count,
        :budget_exceeded_duration
      )
    end

    it "returns empty array when no budget defined" do
      stats = { count: 100, total_duration_ms: 5000 }
      violations = budget.check("undefined#action", stats)
      
      expect(violations).to be_empty
    end
  end

  describe "#enforce!" do
    before do
      budget.for("users#index", count: 10)
    end

    let(:stats) { { count: 15, total_duration_ms: 300 } }
    let(:violations) { budget.check("users#index", stats) }

    context "when mode is :log" do
      before { budget.mode = :log }

      it "logs warnings without raising" do
        expect { budget.enforce!("users#index", violations) }.not_to raise_error
      end
    end

    context "when mode is :notify" do
      before { budget.mode = :notify }

      it "calls the callback without raising" do
        called = false
        budget.on_violation = ->(key, violation) { called = true }
        
        expect { budget.enforce!("users#index", violations) }.not_to raise_error
        expect(called).to be true
      end

      it "passes correct arguments to callback" do
        received_key = nil
        received_violation = nil
        budget.on_violation = ->(key, violation) {
          received_key = key
          received_violation = violation
        }
        
        budget.enforce!("users#index", violations)
        
        expect(received_key).to eq("users#index")
        expect(received_violation[:type]).to eq(:budget_exceeded_count)
      end
    end

    context "when mode is :raise" do
      before { budget.mode = :raise }

      it "raises Budget::Violation" do
        expect {
          budget.enforce!("users#index", violations)
        }.to raise_error(QueryGuard::Budget::Violation, /Query count exceeded/)
      end
    end

    it "does nothing when violations are empty" do
      budget.mode = :raise
      expect { budget.enforce!("users#index", []) }.not_to raise_error
    end
  end
end
