# frozen_string_literal: true

module QueryGuard
  module Analysis
    # Risk severity levels for query analysis
    # Used to classify and report on query risks
    class RiskLevel
      LEVELS = {
        low: 1,
        medium: 2,
        high: 3,
        critical: 4
      }.freeze

      SEVERITY_MAP = {
        low: :info,
        medium: :warn,
        high: :error,
        critical: :error
      }.freeze

      def self.valid?(level)
        LEVELS.key?(level.to_sym)
      end

      def self.to_severity(level)
        SEVERITY_MAP[level.to_sym] || :warn
      end

      def self.compare(level1, level2)
        LEVELS[level1.to_sym] <=> LEVELS[level2.to_sym]
      end
    end
  end
end
