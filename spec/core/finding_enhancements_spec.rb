# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Core::Finding do
  describe "initialization with all fields" do
    it "creates a finding with comprehensive fields" do
      now = Time.now
      finding = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        severity: :error,
        title: "Slow Query Detected",
        description: "Query took too long",
        message: "Query exceeded 100ms",
        file_path: "app/models/user.rb",
        line_number: 42,
        sql: "SELECT * FROM users",
        metadata: { duration_ms: 250 },
        recommendations: ["Add index", "Optimize query"],
        query: nil
      )

      expect(finding.analyzer_name).to eq(:slow_query)
      expect(finding.rule_name).to eq(:duration_exceeded)
      expect(finding.severity).to eq(:error)
      expect(finding.title).to eq("Slow Query Detected")
      expect(finding.description).to eq("Query took too long")
      expect(finding.message).to eq("Query exceeded 100ms")
      expect(finding.file_path).to eq("app/models/user.rb")
      expect(finding.line_number).to eq(42)
      expect(finding.sql).to eq("SELECT * FROM users")
      expect(finding.recommendations).to eq(["Add index", "Optimize query"])
      expect(finding.created_at).to be_a(Time)
    end

    it "freezes all string fields" do
      finding = described_class.new(
        analyzer_name: :test,
        rule_name: :test,
        title: "Title",
        description: "Desc",
        message: "Message",
        file_path: "file.rb",
        sql: "SELECT 1"
      )

      expect(finding.title).to be_frozen
      expect(finding.description).to be_frozen
      expect(finding.message).to be_frozen
      expect(finding.file_path).to be_frozen
      expect(finding.sql).to be_frozen
    end

    it "freezes recommendations array and elements" do
      finding = described_class.new(
        analyzer_name: :test,
        rule_name: :test,
        message: "Test",
        recommendations: ["Rec1", "Rec2"]
      )

      expect(finding.recommendations).to be_frozen
      expect(finding.recommendations[0]).to be_frozen
    end

    it "handles optional fields as nil" do
      finding = described_class.new(
        analyzer_name: :test,
        rule_name: :test,
        message: "Test"
      )

      expect(finding.title).to be_nil
      expect(finding.description).to be_nil
      expect(finding.file_path).to be_nil
      expect(finding.line_number).to be_nil
      expect(finding.sql).to be_nil
      expect(finding.recommendations).to be_empty
    end

    it "converts recommendations to strings" do
      finding = described_class.new(
        analyzer_name: :test,
        rule_name: :test,
        message: "Test",
        recommendations: [1, 2.5, :symbol]
      )

      expect(finding.recommendations).to eq(["1", "2.5", "symbol"])
    end

    it "generates deterministic ID based on content" do
      finding1 = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        message: "Test",
        sql: "SELECT 1",
        file_path: "app.rb",
        line_number: 10
      )

      finding2 = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        message: "Different message (same SQL and location)",
        sql: "SELECT 1",
        file_path: "app.rb",
        line_number: 10
      )

      # Same input = same ID
      expect(finding1.id).to eq(finding2.id)
    end

    it "generates different IDs for different content" do
      finding1 = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        message: "Test",
        sql: "SELECT 1"
      )

      finding2 = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        message: "Test",
        sql: "SELECT 2" # Different SQL
      )

      expect(finding1.id).not_to eq(finding2.id)
    end
  end

  describe "#has_location?" do
    it "returns true when file_path is present" do
      finding = described_class.new(
        analyzer_name: :test,
        rule_name: :test,
        message: "Test",
        file_path: "app.rb"
      )

      expect(finding.has_location?).to be true
    end

    it "returns false when file_path is nil" do
      finding = described_class.new(
        analyzer_name: :test,
        rule_name: :test,
        message: "Test"
      )

      expect(finding.has_location?).to be false
    end
  end

  describe "#to_h" do
    it "serializes all fields to hash" do
      query = instance_double(QueryGuard::Core::Query, to_h: { sql: "SELECT 1" })
      finding = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        severity: :error,
        title: "Slow Query",
        description: "Too slow",
        message: "Exceeded threshold",
        file_path: "app.rb",
        line_number: 42,
        sql: "SELECT 1",
        metadata: { duration_ms: 250 },
        recommendations: ["Optimize"],
        query: query
      )

      hash = finding.to_h
      expect(hash[:id]).to be_present
      expect(hash[:analyzer]).to eq(:slow_query)
      expect(hash[:rule]).to eq(:duration_exceeded)
      expect(hash[:severity]).to eq(:error)
      expect(hash[:title]).to eq("Slow Query")
      expect(hash[:description]).to eq("Too slow")
      expect(hash[:message]).to eq("Exceeded threshold")
      expect(hash[:file_path]).to eq("app.rb")
      expect(hash[:line_number]).to eq(42)
      expect(hash[:sql]).to eq("SELECT 1")
      expect(hash[:metadata]).to eq({ duration_ms: 250 })
      expect(hash[:recommendations]).to eq(["Optimize"])
      expect(hash[:created_at]).to be_present
      expect(hash[:query]).to eq({ sql: "SELECT 1" })
    end

    it "excludes nil values" do
      finding = described_class.new(
        analyzer_name: :test,
        rule_name: :test,
        message: "Test"
      )

      hash = finding.to_h
      expect(hash).not_to have_key(:title)
      expect(hash).not_to have_key(:description)
      expect(hash).not_to have_key(:file_path)
    end
  end

  describe "#to_json_h" do
    it "excludes query object" do
      query = instance_double(QueryGuard::Core::Query, to_h: { sql: "SELECT 1" })
      finding = described_class.new(
        analyzer_name: :test,
        rule_name: :test,
        message: "Test",
        query: query
      )

      json_hash = finding.to_json_h
      expect(json_hash).not_to have_key(:query)
    end

    it "truncates long SQL" do
      finding = described_class.new(
        analyzer_name: :test,
        rule_name: :test,
        message: "Test",
        sql: "SELECT " + "column" * 100
      )

      json_hash = finding.to_json_h
      expect(json_hash[:sql]).to include("...")
      expect(json_hash[:sql].length).to be < 600
    end
  end

  describe "#to_log_s" do
    it "includes severity, analyzer, rule, and message" do
      finding = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        severity: :error,
        message: "Query too slow"
      )

      log_str = finding.to_log_s
      expect(log_str).to include("ERROR")
      expect(log_str).to include("slow_query")
      expect(log_str).to include("duration_exceeded")
      expect(log_str).to include("Query too slow")
    end

    it "includes file location when available" do
      finding = described_class.new(
        analyzer_name: :test,
        rule_name: :test,
        message: "Test",
        file_path: "app/models/user.rb",
        line_number: 42
      )

      log_str = finding.to_log_s
      expect(log_str).to include("app/models/user.rb:42")
    end

    it "includes truncated SQL when available" do
      finding = described_class.new(
        analyzer_name: :test,
        rule_name: :test,
        message: "Test",
        sql: "SELECT * FROM users WHERE id = 1"
      )

      log_str = finding.to_log_s
      expect(log_str).to include("SQL:")
      expect(log_str).to include("SELECT * FROM")
    end
  end

  describe "equality and hashing" do
    it "equals findings with same attributes" do
      f1 = described_class.new(
        analyzer_name: :test,
        rule_name: :test,
        severity: :warn,
        message: "Test"
      )
      f2 = described_class.new(
        analyzer_name: :test,
        rule_name: :test,
        severity: :warn,
        message: "Test"
      )

      expect(f1 == f2).to be true
    end

    it "is hashable for set operations" do
      f1 = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        message: "Test",
        sql: "SELECT 1"
      )
      f2 = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        message: "Test",
        sql: "SELECT 1"
      )
      f3 = described_class.new(
        analyzer_name: :slow_query,
        rule_name: :duration_exceeded,
        message: "Test",
        sql: "SELECT 2"
      )

      set = Set.new([f1, f2, f3])
      expect(set.size).to eq(2) # f1 and f2 have same hash/ID
    end
  end
end
