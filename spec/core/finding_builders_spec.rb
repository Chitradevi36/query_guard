# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Core::FindingBuilders do
  describe ".slow_query" do
    it "creates a well-structured slow query finding" do
      query = QueryGuard::Core::Query.new(
        sql: "SELECT * FROM users WHERE id = 1",
        duration_ms: 250.5,
        name: "User Load"
      )

      finding = described_class.slow_query(
        query,
        duration_ms: 250.5,
        threshold_ms: 100.0
      )

      expect(finding.analyzer_name).to eq(:slow_query)
      expect(finding.rule_name).to eq(:duration_exceeded)
      expect(finding.severity).to eq(:warn)
      expect(finding.title).to eq("Slow Query Detected")
      expect(finding.sql).to eq("SELECT * FROM users WHERE id = 1")
      expect(finding.query).to eq(query)
      expect(finding.metadata[:duration_ms]).to eq(250.5)
      expect(finding.metadata[:threshold_ms]).to eq(100.0)
      expect(finding.recommendations).not_to be_empty
    end

    it "accepts custom severity" do
      query = QueryGuard::Core::Query.new(sql: "SELECT 1", duration_ms: 100)
      finding = described_class.slow_query(
        query,
        duration_ms: 100,
        threshold_ms: 50,
        severity: :error
      )

      expect(finding.severity).to eq(:error)
    end

    it "accepts optional location info" do
      query = QueryGuard::Core::Query.new(sql: "SELECT 1", duration_ms: 100)
      finding = described_class.slow_query(
        query,
        duration_ms: 100,
        threshold_ms: 50,
        file_path: "app/models/user.rb",
        line_number: 42
      )

      expect(finding.file_path).to eq("app/models/user.rb")
      expect(finding.line_number).to eq(42)
    end

    it "includes practical recommendations" do
      query = QueryGuard::Core::Query.new(sql: "SELECT 1", duration_ms: 100)
      finding = described_class.slow_query(
        query,
        duration_ms: 100,
        threshold_ms: 50
      )

      expect(finding.recommendations).to include(
        a_string_matching(/index/i)
      )
      expect(finding.recommendations.count).to be > 2
    end
  end

  describe ".too_many_queries" do
    it "creates a well-structured query count finding" do
      finding = described_class.too_many_queries(
        count: 150,
        limit: 100,
        total_duration_ms: 5000.0
      )

      expect(finding.analyzer_name).to eq(:query_count)
      expect(finding.rule_name).to eq(:count_exceeded)
      expect(finding.severity).to eq(:warn)
      expect(finding.title).to eq("Too Many Queries")
      expect(finding.message).to include("150")
      expect(finding.message).to include("100")
      expect(finding.metadata[:count]).to eq(150)
      expect(finding.metadata[:limit]).to eq(100)
      expect(finding.metadata[:total_duration_ms]).to eq(5000.0)
    end

    it "accepts custom severity" do
      finding = described_class.too_many_queries(
        count: 150,
        limit: 100,
        total_duration_ms: 5000.0,
        severity: :error
      )

      expect(finding.severity).to eq(:error)
    end

    it "includes N+1 prevention recommendations" do
      finding = described_class.too_many_queries(
        count: 150,
        limit: 100,
        total_duration_ms: 5000.0
      )

      expect(finding.recommendations).to include(
        a_string_matching(/eager/i),
        a_string_matching(/N\+1|N\+One/i)
      )
    end
  end

  describe ".select_star" do
    it "creates a well-structured SELECT * finding" do
      query = QueryGuard::Core::Query.new(
        sql: "SELECT * FROM posts",
        duration_ms: 50.0
      )

      finding = described_class.select_star(query)

      expect(finding.analyzer_name).to eq(:select_star)
      expect(finding.rule_name).to eq(:select_star_detected)
      expect(finding.severity).to eq(:warn)
      expect(finding.title).to eq("SELECT * Used")
      expect(finding.sql).to eq("SELECT * FROM posts")
      expect(finding.query).to eq(query)
    end

    it "includes best practice recommendations" do
      query = QueryGuard::Core::Query.new(sql: "SELECT * FROM posts", duration_ms: 50.0)
      finding = described_class.select_star(query)

      expect(finding.recommendations).to include(
        a_string_matching(/specify.*columns/i)
      )
    end

    it "accepts optional location info" do
      query = QueryGuard::Core::Query.new(sql: "SELECT *", duration_ms: 50.0)
      finding = described_class.select_star(
        query,
        file_path: "db/seeds.rb",
        line_number: 15
      )

      expect(finding.file_path).to eq("db/seeds.rb")
      expect(finding.line_number).to eq(15)
    end
  end

  describe ".build" do
    it "creates a generic finding" do
      finding = described_class.build(
        analyzer_name: :custom,
        rule_name: :custom_rule,
        title: "Custom Issue",
        description: "A custom issue was found",
        message: "Custom message",
        severity: :error,
        metadata: { key: "value" }
      )

      expect(finding.analyzer_name).to eq(:custom)
      expect(finding.rule_name).to eq(:custom_rule)
      expect(finding.title).to eq("Custom Issue")
      expect(finding.severity).to eq(:error)
      expect(finding.metadata[:key]).to eq("value")
    end

    it "accepts query object" do
      query = QueryGuard::Core::Query.new(sql: "SELECT 1", duration_ms: 10)
      finding = described_class.build(
        analyzer_name: :custom,
        rule_name: :rule,
        message: "Message",
        query: query
      )

      expect(finding.query).to eq(query)
    end
  end

  describe ".migration_risk" do
    it "creates a migration safety finding" do
      finding = described_class.migration_risk(
        migration_file: "db/migrate/001_create_users.rb",
        issue: "Removing NOT NULL constraint without safe guards"
      )

      expect(finding.analyzer_name).to eq(:migration_safety)
      expect(finding.rule_name).to eq(:unsafe_operation)
      expect(finding.severity).to eq(:error)
      expect(finding.file_path).to eq("db/migrate/001_create_users.rb")
      expect(finding.message).to include("Removing NOT NULL")
    end

    it "accepts custom rule and title" do
      finding = described_class.migration_risk(
        migration_file: "db/migrate/001.rb",
        issue: "Index on low cardinality column",
        rule_name: :low_cardinality_index,
        title: "Inefficient Index"
      )

      expect(finding.rule_name).to eq(:low_cardinality_index)
      expect(finding.title).to eq("Inefficient Index")
    end

    it "includes migration-specific recommendations" do
      finding = described_class.migration_risk(
        migration_file: "db/migrate/001.rb",
        issue: "Test issue"
      )

      expect(finding.recommendations).to include(
        a_string_matching(/staging/i),
        a_string_matching(/review/i)
      )
    end

    it "accepts line number" do
      finding = described_class.migration_risk(
        migration_file: "db/migrate/001.rb",
        issue: "Test",
        line_number: 10
      )

      expect(finding.line_number).to eq(10)
    end
  end

  describe ".pattern_detected" do
    it "creates a pattern detection finding" do
      query = QueryGuard::Core::Query.new(sql: "SELECT 1", duration_ms: 10)
      finding = described_class.pattern_detected(
        query,
        pattern_type: "potential_n_plus_one"
      )

      expect(finding.analyzer_name).to eq(:pattern_detector)
      expect(finding.rule_name).to eq(:pattern_detected)
      expect(finding.metadata[:pattern_type]).to eq("potential_n_plus_one")
    end

    it "accepts custom analyzer and rule names" do
      query = QueryGuard::Core::Query.new(sql: "SELECT 1", duration_ms: 10)
      finding = described_class.pattern_detected(
        query,
        pattern_type: "join_explosion",
        analyzer_name: :join_analyzer,
        rule_name: :complex_join
      )

      expect(finding.analyzer_name).to eq(:join_analyzer)
      expect(finding.rule_name).to eq(:complex_join)
    end
  end

  describe "serialization from builders" do
    it "slow_query finding serializes cleanly to JSON" do
      query = QueryGuard::Core::Query.new(sql: "SELECT 1", duration_ms: 100)
      finding = described_class.slow_query(
        query,
        duration_ms: 100,
        threshold_ms: 50
      )

      json_hash = finding.to_json_h
      expect(json_hash).to have_key(:analyzer)
      expect(json_hash).to have_key(:rule)
      expect(json_hash).to have_key(:severity)
      expect(json_hash).to have_key(:title)
      expect(json_hash).to have_key(:recommendations)
      expect(json_hash).not_to have_key(:query)
    end

    it "migration_risk finding serializes cleanly to JSON" do
      finding = described_class.migration_risk(
        migration_file: "db/migrate/001.rb",
        issue: "Unsafe drop"
      )

      json_hash = finding.to_json_h
      expect(json_hash).to have_key(:file_path)
      expect(json_hash[:file_path]).to eq("db/migrate/001.rb")
    end
  end
end
