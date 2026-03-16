# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Config do
  describe "initialization" do
    it "creates default analyzer registry" do
      config = described_class.new
      
      expect(config.analyzer_registry).to be_a(QueryGuard::Analyzers::Registry)
      expect(config.analyzer_registry.registered?(:slow_query)).to be true
      expect(config.analyzer_registry.registered?(:query_count)).to be true
      expect(config.analyzer_registry.registered?(:select_star)).to be true
    end

    it "sets default severity levels" do
      config = described_class.new
      
      expect(config.slow_query_severity).to eq(:warn)
      expect(config.query_count_severity).to eq(:warn)
      expect(config.select_star_severity).to eq(:warn)
    end

    it "initializes disabled_analyzers as empty" do
      config = described_class.new
      
      expect(config.disabled_analyzers).to eq([])
    end
  end

  describe "#disable_analyzer" do
    it "adds analyzer to disabled list" do
      config = described_class.new
      config.disable_analyzer(:slow_query)

      expect(config.disabled_analyzers).to include(:slow_query)
    end

    it "allows string names" do
      config = described_class.new
      config.disable_analyzer("query_count")

      expect(config.disabled_analyzers).to include(:query_count)
    end

    it "doesn't add duplicates" do
      config = described_class.new
      config.disable_analyzer(:slow_query)
      config.disable_analyzer(:slow_query)

      count = config.disabled_analyzers.count { |a| a == :slow_query }
      expect(count).to eq(1)
    end
  end

  describe "#enable_analyzer" do
    it "removes analyzer from disabled list" do
      config = described_class.new
      config.disable_analyzer(:slow_query)
      config.enable_analyzer(:slow_query)

      expect(config.disabled_analyzers).not_to include(:slow_query)
    end

    it "is idempotent" do
      config = described_class.new
      config.enable_analyzer(:slow_query)
      config.enable_analyzer(:slow_query)

      expect(config.disabled_analyzers).to be_empty
    end
  end

  describe "#register_analyzer" do
    it "registers a custom analyzer" do
      config = described_class.new
      custom_analyzer = QueryGuard::Analyzers::Base.new(:custom)
      
      config.register_analyzer(:custom, custom_analyzer)

      expect(config.analyzer_registry.registered?(:custom)).to be true
      expect(config.analyzer_registry.get(:custom)).to eq(custom_analyzer)
    end
  end

  describe "default values" do
    it "preserves existing config attributes" do
      config = described_class.new
      
      expect(config.enabled_environments).to eq(%i[development test])
      expect(config.max_queries_per_request).to eq(100)
      expect(config.max_duration_ms_per_query).to eq(100.0)
      expect(config.block_select_star).to be false
      expect(config.raise_on_violation).to be false
    end
  end
end
