# frozen_string_literal: true

module QueryGuard
  module Analyzers
    # Registry for managing analyzer instances.
    # Provides global registration and per-request analysis coordination.
    class Registry
      def initialize
        @analyzers = {}
      end

      # Register an analyzer instance
      # @param name [Symbol] Unique identifier for the analyzer
      # @param analyzer [Base] Analyzer instance
      def register(name, analyzer)
        raise ArgumentError, "Analyzer must inherit from Base" unless analyzer.is_a?(Base)
        @analyzers[name.to_sym] = analyzer
      end

      # Retrieve analyzer by name
      # @param name [Symbol] Analyzer name
      # @return [Base, nil] Analyzer instance or nil if not found
      def get(name)
        @analyzers[name.to_sym]
      end

      # Check if analyzer is registered
      def registered?(name)
        @analyzers.key?(name.to_sym)
      end

      # Get all registered analyzers
      # @return [Hash{Symbol => Base}]
      def all
        @analyzers.dup
      end

      # Run all enabled analyzers against the context
      # @param context [Core::Context] Request context
      # @param config [Config] Configuration
      # @return [Array<Core::Finding>] Combined findings from all analyzers
      def analyze(context, config)
        findings = []
        @analyzers.each do |name, analyzer|
          next unless analyzer.enabled?(config)
          findings.concat(analyzer.analyze(context, config))
        end
        findings
      end

      # Clear all registered analyzers
      def clear
        @analyzers.clear
      end
    end
  end
end
