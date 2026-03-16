# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Core::Context do
  describe "#add_query" do
    it "adds a query to the context" do
      context = described_class.new
      query = context.add_query(sql: "SELECT 1", duration_ms: 10.5)

      expect(context.queries).to have_length(1)
      expect(query).to be_a(QueryGuard::Core::Query)
      expect(query.sql).to eq("SELECT 1")
    end

    it "accepts optional metadata" do
      context = described_class.new
      now = Time.now
      query = context.add_query(
        sql: "SELECT * FROM users",
        duration_ms: 50,
        name: "User Load",
        started_at: now,
        finished_at: now + 0.05
      )

      expect(query.name).to eq("User Load")
      expect(query.started_at).to eq(now)
    end
  end

  describe "#add_finding" do
    it "adds a finding to the context" do
      context = described_class.new
      finding = QueryGuard::Core::Finding.new(
        analyzer_name: :test,
        rule_name: :test,
        message: "Test finding"
      )

      context.add_finding(finding)
      expect(context.findings).to include(finding)
    end

    it "raises on non-Finding object" do
      context = described_class.new
      expect { context.add_finding("not a finding") }.to raise_error(ArgumentError)
    end
  end

  describe "#create_finding" do
    it "creates and adds a finding in one call" do
      context = described_class.new
      finding = context.create_finding(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        message: "Too slow"
      )

      expect(finding).to be_a(QueryGuard::Core::Finding)
      expect(context.findings).to include(finding)
    end

    it "passes all parameters to Finding initializer" do
      context = described_class.new
      finding = context.create_finding(
        analyzer_name: :test,
        rule_name: :test,
        severity: :error,
        message: "Test",
        metadata: { key: "value" }
      )

      expect(finding.severity).to eq(:error)
      expect(finding.metadata).to eq({ key: "value" })
    end
  end

  describe "#query_count" do
    it "returns number of queries" do
      context = described_class.new
      context.add_query(sql: "SELECT 1", duration_ms: 10)
      context.add_query(sql: "SELECT 2", duration_ms: 20)

      expect(context.query_count).to eq(2)
    end
  end

  describe "#total_duration_ms" do
    it "sums duration of all queries" do
      context = described_class.new
      context.add_query(sql: "SELECT 1", duration_ms: 10.5)
      context.add_query(sql: "SELECT 2", duration_ms: 20.5)
      context.add_query(sql: "SELECT 3", duration_ms: 30.0)

      expect(context.total_duration_ms).to eq(61.0)
    end
  end

  describe "#finding_count" do
    it "returns number of findings" do
      context = described_class.new
      context.create_finding(analyzer_name: :test1, rule_name: :test, message: "One")
      context.create_finding(analyzer_name: :test2, rule_name: :test, message: "Two")

      expect(context.finding_count).to eq(2)
    end
  end

  describe "#findings_by_severity" do
    it "filters findings by severity" do
      context = described_class.new
      context.create_finding(
        analyzer_name: :test1,
        rule_name: :test,
        severity: :error,
        message: "Error"
      )
      context.create_finding(
        analyzer_name: :test2,
        rule_name: :test,
        severity: :warn,
        message: "Warning"
      )
      context.create_finding(
        analyzer_name: :test3,
        rule_name: :test,
        severity: :error,
        message: "Another error"
      )

      errors = context.findings_by_severity(:error)
      expect(errors).to have_length(2)
      expect(errors.all? { |f| f.severity == :error }).to be true
    end

    it "returns empty array for severity with no findings" do
      context = described_class.new
      context.create_finding(analyzer_name: :test, rule_name: :test, message: "Message")

      expect(context.findings_by_severity(:error)).to be_empty
    end
  end

  describe "#clear" do
    it "clears all queries and findings" do
      context = described_class.new
      context.add_query(sql: "SELECT 1", duration_ms: 10)
      context.create_finding(analyzer_name: :test, rule_name: :test, message: "Finding")

      context.clear
      expect(context.queries).to be_empty
      expect(context.findings).to be_empty
    end
  end

  describe "#to_h" do
    it "serializes context to hash" do
      context = described_class.new
      context.add_query(sql: "SELECT 1", duration_ms: 10.5)
      context.add_query(sql: "SELECT 2", duration_ms: 20.5)
      context.create_finding(
        analyzer_name: :test,
        rule_name: :test,
        severity: :warn,
        message: "Test"
      )

      hash = context.to_h
      expect(hash[:query_count]).to eq(2)
      expect(hash[:total_duration_ms]).to eq(31.0)
      expect(hash[:findings]).to have_length(1)
      expect(hash[:findings][0][:analyzer]).to eq(:test)
    end
  end
end
