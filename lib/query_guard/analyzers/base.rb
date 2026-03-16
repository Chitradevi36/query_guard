# frozen_string_literal: true

module QueryGuard
  module Analyzers
    # Base class for all rule-based analyzers.
    # Subclasses implement `analyze(context, config)` to produce findings.
    class Base
      attr_reader :name

      def initialize(name)
        @name = name.to_sym
      end

      # Analyze the context and produce findings.
      # Must return an array of Finding objects.
      #
      # @param context [Core::Context] Contains queries and metadata
      # @param config [Config] Configuration object
      # @return [Array<Core::Finding>] List of findings
      def analyze(context, config)
        raise NotImplementedError, "#{self.class} must implement #analyze"
      end

      # Enabled check - allows per-analyzer enable/disable
      def enabled?(config)
        !config.disabled_analyzers&.include?(name)
      end
    end
  end
end
