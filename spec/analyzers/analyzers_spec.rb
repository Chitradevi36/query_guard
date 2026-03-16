# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Analyzers::SlowQueryAnalyzer do
  let(:analyzer) { described_class.new }
  let(:config) { QueryGuard::Config.new }

  describe "initialization" do
    it "has name :slow_query" do
      expect(analyzer.name).to eq(:slow_query)
    end
  end

  describe "#analyze" do
    it "detects slow queries" do
      context = QueryGuard::Core::Context.new
      context.add_query(sql: "SELECT 1", duration_ms: 50.0)
      context.add_query(sql: "SELECT 2", duration_ms: 150.0) # Slow
      
      config.max_duration_ms_per_query = 100.0
      findings = analyzer.analyze(context, config)

      expect(findings).to have_length(1)
      expect(findings[0].rule_name).to eq(:duration_exceeded)
      expect(findings[0].analyzer_name).to eq(:slow_query)
      expect(findings[0].title).to eq("Slow Query Detected")
      expect(findings[0].metadata[:duration_ms]).to eq(150.0)
    end

    it "returns empty if no slow queries" do
      context = QueryGuard::Core::Context.new
      context.add_query(sql: "SELECT 1", duration_ms: 50.0)
      context.add_query(sql: "SELECT 2", duration_ms: 80.0)
      
      config.max_duration_ms_per_query = 100.0
      findings = analyzer.analyze(context, config)

      expect(findings).to be_empty
    end

    it "respects disabled threshold (nil)" do
      context = QueryGuard::Core::Context.new
      context.add_query(sql: "SELECT 1", duration_ms: 5000.0)
      
      config.max_duration_ms_per_query = nil
      findings = analyzer.analyze(context, config)

      expect(findings).to be_empty
    end

    it "ignores queries matching ignored_sql patterns" do
      context = QueryGuard::Core::Context.new
      context.add_query(sql: "PRAGMA table_info(users)", duration_ms: 150.0)
      context.add_query(sql: "SELECT 1", duration_ms: 150.0)
      
      config.max_duration_ms_per_query = 100.0
      config.ignored_sql = [/^PRAGMA /i]
      findings = analyzer.analyze(context, config)

      expect(findings).to have_length(1)
      expect(findings[0].metadata[:sql]).to eq("SELECT 1")
    end

    it "includes recommendations" do
      context = QueryGuard::Core::Context.new
      context.add_query(sql: "SELECT * FROM users", duration_ms: 150.0)
      
      config.max_duration_ms_per_query = 100.0
      findings = analyzer.analyze(context, config)

      expect(findings[0].recommendations).not_to be_empty
      expect(findings[0].recommendations).to include(
        a_string_matching(/index/i)
      )
    end

    it "respects configured severity" do
      context = QueryGuard::Core::Context.new
      context.add_query(sql: "SELECT 1", duration_ms: 150.0)
      
      config.max_duration_ms_per_query = 100.0
      config.slow_query_severity = :error
      findings = analyzer.analyze(context, config)

      expect(findings[0].severity).to eq(:error)
    end
  end
end

RSpec.describe QueryGuard::Analyzers::QueryCountAnalyzer do
  let(:analyzer) { described_class.new }
  let(:config) { QueryGuard::Config.new }

  describe "initialization" do
    it "has name :query_count" do
      expect(analyzer.name).to eq(:query_count)
    end
  end

  describe "#analyze" do
    it "detects too many queries" do
      context = QueryGuard::Core::Context.new
      (1..150).each { |i| context.add_query(sql: "SELECT #{i}", duration_ms: 1.0) }
      
      config.max_queries_per_request = 100
      findings = analyzer.analyze(context, config)

      expect(findings).to have_length(1)
      expect(findings[0].rule_name).to eq(:count_exceeded)
      expect(findings[0].analyzer_name).to eq(:query_count)
      expect(findings[0].title).to eq("Too Many Queries")
      expect(findings[0].metadata[:count]).to eq(150)
      expect(findings[0].metadata[:limit]).to eq(100)
    end

    it "returns empty if within limit" do
      context = QueryGuard::Core::Context.new
      (1..50).each { |i| context.add_query(sql: "SELECT #{i}", duration_ms: 1.0) }
      
      config.max_queries_per_request = 100
      findings = analyzer.analyze(context, config)

      expect(findings).to be_empty
    end

    it "respects disabled limit (nil)" do
      context = QueryGuard::Core::Context.new
      (1..1000).each { |i| context.add_query(sql: "SELECT #{i}", duration_ms: 1.0) }
      
      config.max_queries_per_request = nil
      findings = analyzer.analyze(context, config)

      expect(findings).to be_empty
    end

    it "includes total duration in metadata" do
      context = QueryGuard::Core::Context.new
      context.add_query(sql: "SELECT 1", duration_ms: 10.5)
      context.add_query(sql: "SELECT 2", duration_ms: 20.5)
      (1..100).each { |i| context.add_query(sql: "SELECT #{i}", duration_ms: 1.0) }
      
      config.max_queries_per_request = 100
      findings = analyzer.analyze(context, config)

      expect(findings[0].metadata[:total_duration_ms]).to be_within(0.1).of(131.0)
    end

    it "includes N+1 prevention recommendations" do
      context = QueryGuard::Core::Context.new
      (1..150).each { |i| context.add_query(sql: "SELECT #{i}", duration_ms: 1.0) }
      
      config.max_queries_per_request = 100
      findings = analyzer.analyze(context, config)

      expect(findings[0].recommendations).to include(
        a_string_matching(/eager/i)
      )
    end

    it "respects configured severity" do
      context = QueryGuard::Core::Context.new
      (1..150).each { |i| context.add_query(sql: "SELECT #{i}", duration_ms: 1.0) }
      
      config.max_queries_per_request = 100
      config.query_count_severity = :error
      findings = analyzer.analyze(context, config)

      expect(findings[0].severity).to eq(:error)
    end
  end
end

RSpec.describe QueryGuard::Analyzers::SelectStarAnalyzer do
  let(:analyzer) { described_class.new }
  let(:config) { QueryGuard::Config.new }

  describe "initialization" do
    it "has name :select_star" do
      expect(analyzer.name).to eq(:select_star)
    end
  end

  describe "#analyze" do
    it "detects SELECT * queries" do
      context = QueryGuard::Core::Context.new
      context.add_query(sql: "SELECT id, name FROM users", duration_ms: 10.0)
      context.add_query(sql: "SELECT * FROM posts", duration_ms: 10.0)
      
      config.block_select_star = true
      findings = analyzer.analyze(context, config)

      expect(findings).to have_length(1)
      expect(findings[0].rule_name).to eq(:select_star_detected)
      expect(findings[0].analyzer_name).to eq(:select_star)
      expect(findings[0].title).to eq("SELECT * Used")
      expect(findings[0].metadata[:sql]).to include("SELECT *")
    end

    it "is case-insensitive" do
      context = QueryGuard::Core::Context.new
      context.add_query(sql: "select * from users", duration_ms: 10.0)
      context.add_query(sql: "SeLeCt * FrOm posts", duration_ms: 10.0)
      
      config.block_select_star = true
      findings = analyzer.analyze(context, config)

      expect(findings).to have_length(2)
    end

    it "returns empty when not configured" do
      context = QueryGuard::Core::Context.new
      context.add_query(sql: "SELECT * FROM users", duration_ms: 10.0)
      
      config.block_select_star = false
      findings = analyzer.analyze(context, config)

      expect(findings).to be_empty
    end

    it "ignores queries matching ignored_sql patterns" do
      context = QueryGuard::Core::Context.new
      context.add_query(sql: "PRAGMA table_info(*)", duration_ms: 10.0)
      context.add_query(sql: "SELECT * FROM users", duration_ms: 10.0)
      
      config.block_select_star = true
      config.ignored_sql = [/^PRAGMA /i]
      findings = analyzer.analyze(context, config)

      expect(findings).to have_length(1)
      expect(findings[0].metadata[:sql]).to eq("SELECT * FROM users")
    end

    it "includes column-specification recommendations" do
      context = QueryGuard::Core::Context.new
      context.add_query(sql: "SELECT * FROM users", duration_ms: 10.0)
      
      config.block_select_star = true
      findings = analyzer.analyze(context, config)

      expect(findings[0].recommendations).to include(
        a_string_matching(/specify/)
      )
    end

    it "respects configured severity" do
      context = QueryGuard::Core::Context.new
      context.add_query(sql: "SELECT * FROM users", duration_ms: 10.0)
      
      config.block_select_star = true
      config.select_star_severity = :error
      findings = analyzer.analyze(context, config)

      expect(findings[0].severity).to eq(:error)
    end
  end
end
