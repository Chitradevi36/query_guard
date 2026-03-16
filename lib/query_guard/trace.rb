# frozen_string_literal: true
require "securerandom"

module QueryGuard
  # Block-based tracing API for manual query tracking.
  # Usable in console, tests, and Rails controllers/jobs.
  module Trace
    class Report
      attr_reader :label, :context, :stats, :violations

      def initialize(label, context, stats, violations)
        @label = label
        @context = context
        @stats = stats
        @violations = violations
      end

      def query_count
        @stats[:count]
      end

      def total_duration_ms
        @stats[:total_duration_ms]
      end

      def queries
        @stats[:queries] || []
      end

      def fingerprints
        @stats[:fingerprints] || {}
      end

      def has_violations?
        !@violations.empty?
      end

      def to_h
        {
          label: @label,
          context: @context,
          query_count: query_count,
          total_duration_ms: total_duration_ms,
          violations: @violations,
          fingerprints: @fingerprints
        }
      end
    end

    module_function

    # Trace a block of code and capture query stats.
    # Returns [result, report] tuple.
    #
    # Example:
    #   result, report = QueryGuard.trace("load users") do
    #     User.where(active: true).limit(10).to_a
    #   end
    #
    #   puts report.query_count
    #   puts report.total_duration_ms
    #
    # With context:
    #   result, report = QueryGuard.trace("process batch", context: { batch_id: 123 }) do
    #     # ... code ...
    #   end
    def trace(label, context: {})
      # Initialize thread-local stats
      previous_stats = Thread.current[:query_guard_stats]
      Thread.current[:query_guard_stats] = {
        request_id: "trace-#{SecureRandom.hex(4)}",
        count: 0,
        total_duration_ms: 0.0,
        violations: [],
        fingerprints: Hash.new(0),
        response_bytes: 0,
        queries: [],
        request: context
      }

      # Execute the block
      result = yield

      # Capture stats
      stats = Thread.current[:query_guard_stats]
      violations = stats[:violations].dup

      # Check budget if configured
      if QueryGuard.respond_to?(:config) && QueryGuard.config
        budget = QueryGuard.config.budget
        if budget
          budget_violations = budget.check(label, stats)
          violations.concat(budget_violations)
        end
      end

      # Build report
      report = Report.new(label, context, stats, violations)

      [result, report]
    ensure
      # Restore previous stats
      Thread.current[:query_guard_stats] = previous_stats
    end
  end
end
