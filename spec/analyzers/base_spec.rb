# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Analyzers::Base do
  describe "initialization" do
    it "stores the analyzer name" do
      analyzer = described_class.new(:my_analyzer)
      expect(analyzer.name).to eq(:my_analyzer)
    end
  end

  describe "#analyze" do
    it "raises NotImplementedError" do
      analyzer = described_class.new(:test)
      context = QueryGuard::Core::Context.new
      config = QueryGuard::Config.new

      expect do
        analyzer.analyze(context, config)
      end.to raise_error(NotImplementedError)
    end
  end

  describe "#enabled?" do
    it "returns true by default" do
      analyzer = described_class.new(:test)
      config = QueryGuard::Config.new

      expect(analyzer.enabled?(config)).to be true
    end

    it "returns false if analyzer disabled in config" do
      analyzer = described_class.new(:test)
      config = QueryGuard::Config.new
      config.disable_analyzer(:test)

      expect(analyzer.enabled?(config)).to be false
    end
  end
end

RSpec.describe QueryGuard::Analyzers::Registry do
  describe "#register" do
    it "stores an analyzer" do
      registry = described_class.new
      analyzer = QueryGuard::Analyzers::Base.new(:test)
      registry.register(:test, analyzer)

      expect(registry.registered?(:test)).to be true
    end

    it "raises on non-Base analyzer" do
      registry = described_class.new
      expect { registry.register(:test, "not an analyzer") }.to raise_error(ArgumentError)
    end

    it "sanitizes analyzer name to symbol" do
      registry = described_class.new
      analyzer = QueryGuard::Analyzers::Base.new(:test)
      registry.register("test_string", analyzer)

      expect(registry.registered?(:test_string)).to be true
    end
  end

  describe "#get" do
    it "retrieves a registered analyzer" do
      registry = described_class.new
      analyzer = QueryGuard::Analyzers::Base.new(:my_analyzer)
      registry.register(:my_analyzer, analyzer)

      retrieved = registry.get(:my_analyzer)
      expect(retrieved).to eq(analyzer)
    end

    it "returns nil for unregistered analyzer" do
      registry = described_class.new
      expect(registry.get(:nonexistent)).to be_nil
    end
  end

  describe "#all" do
    it "returns copy of all registered analyzers" do
      registry = described_class.new
      analyzer1 = QueryGuard::Analyzers::Base.new(:one)
      analyzer2 = QueryGuard::Analyzers::Base.new(:two)
      registry.register(:one, analyzer1)
      registry.register(:two, analyzer2)

      all = registry.all
      expect(all).to have_key(:one)
      expect(all).to have_key(:two)
    end

    it "returns a copy, not reference to internal state" do
      registry = described_class.new
      analyzer = QueryGuard::Analyzers::Base.new(:test)
      registry.register(:test, analyzer)

      all1 = registry.all
      all1.delete(:test)

      expect(registry.registered?(:test)).to be true
    end
  end

  describe "#clear" do
    it "removes all registered analyzers" do
      registry = described_class.new
      analyzer = QueryGuard::Analyzers::Base.new(:test)
      registry.register(:test, analyzer)

      registry.clear
      expect(registry.registered?(:test)).to be false
    end
  end

  describe "#analyze" do
    it "runs all enabled analyzers" do
      registry = described_class.new
      
      # Create mock analyzers
      analyzer1 = instance_double(QueryGuard::Analyzers::Base)
      analyzer2 = instance_double(QueryGuard::Analyzers::Base)
      
      finding1 = QueryGuard::Core::Finding.new(
        analyzer_name: :one,
        rule_name: :test,
        message: "Finding 1"
      )
      finding2 = QueryGuard::Core::Finding.new(
        analyzer_name: :two,
        rule_name: :test,
        message: "Finding 2"
      )
      
      allow(analyzer1).to receive(:enabled?).and_return(true)
      allow(analyzer1).to receive(:analyze).and_return([finding1])
      allow(analyzer2).to receive(:enabled?).and_return(true)
      allow(analyzer2).to receive(:analyze).and_return([finding2])
      
      registry.instance_variable_set(:@analyzers, { one: analyzer1, two: analyzer2 })
      
      context = QueryGuard::Core::Context.new
      config = QueryGuard::Config.new
      
      findings = registry.analyze(context, config)
      
      expect(findings).to have_length(2)
      expect(findings).to include(finding1, finding2)
    end

    it "skips disabled analyzers" do
      registry = described_class.new
      
      analyzer = instance_double(QueryGuard::Analyzers::Base)
      allow(analyzer).to receive(:enabled?).and_return(false)
      allow(analyzer).to receive(:analyze).never
      
      registry.instance_variable_set(:@analyzers, { test: analyzer })
      
      context = QueryGuard::Core::Context.new
      config = QueryGuard::Config.new
      
      findings = registry.analyze(context, config)
      
      expect(findings).to be_empty
    end
  end
end
