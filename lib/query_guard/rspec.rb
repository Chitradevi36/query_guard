# frozen_string_literal: true

require "rspec/expectations"
require "query_guard/trace"

# RSpec matcher for asserting query budgets.
#
# Usage:
#   expect {
#     User.where(active: true).to_a
#   }.to_not exceed_query_budget(count: 5)
#
#   expect {
#     User.all.to_a
#   }.to_not exceed_query_budget(count: 10, duration_ms: 500)
#
# With a labeled budget:
#   QueryGuard.config.budget.for("users#index", count: 5)
#   
#   expect {
#     # code
#   }.to_not exceed_query_budget("users#index")
RSpec::Matchers.define :exceed_query_budget do |budget_key_or_limits = nil, **limits|
  match do |block|
    # Determine if we're checking a named budget or inline limits
    if budget_key_or_limits.is_a?(String)
      budget_key = budget_key_or_limits
      budget_limits = QueryGuard.config&.budget&.budget_for(budget_key)
      
      if budget_limits.nil?
        raise ArgumentError, "No budget defined for '#{budget_key}'. Define it with QueryGuard.config.budget.for('#{budget_key}', ...)"
      end
      
      limits = budget_limits
    elsif budget_key_or_limits.is_a?(Hash)
      limits = budget_key_or_limits.merge(limits)
    end

    # Execute the block within a trace
    _, report = QueryGuard::Trace.trace("rspec_matcher") do
      block.call
    end

    @actual_count = report.query_count
    @actual_duration = report.total_duration_ms
    @limit_count = limits[:count]
    @limit_duration = limits[:duration_ms]

    # Check if any budget was exceeded
    @exceeded = false
    @violations = []

    if @limit_count && @actual_count > @limit_count
      @exceeded = true
      @violations << "count: #{@actual_count} > #{@limit_count}"
    end

    if @limit_duration && @actual_duration > @limit_duration
      @exceeded = true
      @violations << "duration: #{@actual_duration.round(2)}ms > #{@limit_duration}ms"
    end

    @exceeded
  end

  failure_message do
    "expected query budget not to be exceeded, but it was:\n  #{@violations.join("\n  ")}"
  end

  failure_message_when_negated do
    parts = []
    parts << "count: #{@actual_count} <= #{@limit_count}" if @limit_count
    parts << "duration: #{@actual_duration.round(2)}ms <= #{@limit_duration}ms" if @limit_duration
    "expected query budget to be exceeded, but it was within limits:\n  #{parts.join("\n  ")}"
  end

  description do
    parts = []
    parts << "count <= #{@limit_count}" if @limit_count
    parts << "duration <= #{@limit_duration}ms" if @limit_duration
    "not exceed query budget (#{parts.join(", ")})"
  end

  supports_block_expectations
end

module QueryGuard
  module RSpec
    # Convenience helper to check if code stays within a query budget
    def within_query_budget(**limits, &block)
      _, report = QueryGuard::Trace.trace("within_query_budget") do
        block.call
      end

      violations = []

      if limits[:count] && report.query_count > limits[:count]
        violations << "Query count exceeded: #{report.query_count} > #{limits[:count]}"
      end

      if limits[:duration_ms] && report.total_duration_ms > limits[:duration_ms]
        violations << "Duration exceeded: #{report.total_duration_ms.round(2)}ms > #{limits[:duration_ms]}ms"
      end

      if violations.any?
        raise QueryGuard::Budget::Violation, violations.join("; ")
      end

      report
    end
  end
end

# Auto-include helpers when RSpec is available
if defined?(::RSpec)
  ::RSpec.configure do |config|
    config.include QueryGuard::RSpec
  end
end
