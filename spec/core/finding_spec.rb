# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Core::Finding do
  describe "initialization" do
    it "creates a finding with required attributes" do
      finding = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        message: "Query too slow"
      )

      expect(finding.analyzer_name).to eq(:slow_query)
      expect(finding.rule_name).to eq(:duration_exceeded)
      expect(finding.severity).to eq(:warn) # default
      expect(finding.message).to eq("Query too slow")
    end

    it "accepts custom severity" do
      finding = described_class.new(
        analyzer_name: :query_count,
        rule_name: :count_exceeded,
        severity: :error,
        message: "Too many queries"
      )

      expect(finding.severity).to eq(:error)
    end

    it "freezes message for immutability" do
      finding = described_class.new(
        analyzer_name: :test,
        rule_name: :test,
        message: "Test"
      )
      expect(finding.message).to be_frozen
    end

    it "raises on invalid severity" do
      expect do
        described_class.new(
          analyzer_name: :test,
          rule_name: :test,
          severity: :invalid,
          message: "Test"
        )
      end.to raise_error(ArgumentError)
    end

    it "accepts metadata hash" do
      metadata = { count: 150, limit: 100 }
      finding = described_class.new(
        analyzer_name: :query_count,
        rule_name: :count_exceeded,
        metadata: metadata,
        message: "Too many"
      )

      expect(finding.metadata).to eq(metadata)
      expect(finding.metadata).to be_frozen
    end

    it "accepts optional query object" do
      query = instance_double(QueryGuard::Core::Query)
      finding = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        message: "Slow",
        query: query
      )

      expect(finding.query).to eq(query)
    end
  end

  describe "valid severities" do
    QueryGuard::Core::Finding::SEVERITIES.each do |severity|
      it "accepts severity :#{severity}" do
        finding = described_class.new(
          analyzer_name: :test,
          rule_name: :test,
          severity: severity,
          message: "Test"
        )
        expect(finding.severity).to eq(severity)
      end
    end
  end

  describe "#==" do
    it "compares findings by attributes" do
      finding1 = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        severity: :error,
        message: "Query too slow"
      )
      finding2 = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        severity: :error,
        message: "Query too slow"
      )

      expect(finding1 == finding2).to be true
    end

    it "returns false for different findings" do
      finding1 = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        message: "Query too slow"
      )
      finding2 = described_class.new(
        analyzer_name: :query_count,
        rule_name: :count_exceeded,
        message: "Too many queries"
      )

      expect(finding1 == finding2).to be false
    end
  end

  describe "#to_h" do
    it "serializes to hash" do
      query = instance_double(QueryGuard::Core::Query, to_h: { sql: "SELECT 1" })
      finding = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        severity: :error,
        message: "Too slow",
        metadata: { duration_ms: 250 },
        query: query
      )

      hash = finding.to_h
      expect(hash[:analyzer]).to eq(:slow_query)
      expect(hash[:rule]).to eq(:duration_exceeded)
      expect(hash[:severity]).to eq(:error)
      expect(hash[:message]).to eq("Too slow")
      expect(hash[:metadata]).to eq({ duration_ms: 250 })
      expect(hash[:query]).to eq({ sql: "SELECT 1" })
    end
  end

  describe "#to_s" do
    it "returns human-readable string" do
      finding = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        severity: :error,
        message: "Query exceeded threshold"
      )

      expect(finding.to_s).to include("ERROR")
      expect(finding.to_s).to include("slow_query")
      expect(finding.to_s).to include("Query exceeded threshold")
    end
  end
end
