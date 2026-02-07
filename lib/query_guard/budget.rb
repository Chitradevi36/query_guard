# frozen_string_literal: true

module QueryGuard
  # Budget system for enforcing query SLOs on controllers and jobs.
  # Supports modes: :log (warn only), :notify (callback), :raise (exception).
  class Budget
    class Violation < StandardError; end

    attr_reader :rules, :mode, :on_violation

    def initialize
      @rules = {}
      @mode = :log
      @on_violation = nil
    end

    # DSL: Define a budget for a specific controller action.
    # Examples:
    #   budget.for("users#index", count: 10, duration_ms: 500)
    #   budget.for("posts#show", count: 5)
    def for(key, **limits)
      normalized = normalize_key(key)
      @rules[normalized] ||= {}
      @rules[normalized].merge!(limits)
      self
    end

    # DSL: Define a budget for a background job.
    # Examples:
    #   budget.for_job("EmailJob", count: 50, duration_ms: 2000)
    #   budget.for_job(EmailJob, count: 50)
    def for_job(job_class_or_name, **limits)
      key = job_class_or_name.is_a?(String) ? job_class_or_name : job_class_or_name.to_s
      normalized = normalize_key("job:#{key}")
      @rules[normalized] ||= {}
      @rules[normalized].merge!(limits)
      self
    end

    # Set the enforcement mode
    # :log - Log warnings only (default)
    # :notify - Call on_violation callback
    # :raise - Raise Budget::Violation exception
    def mode=(value)
      unless [:log, :notify, :raise].include?(value)
        raise ArgumentError, "Invalid mode: #{value}. Must be :log, :notify, or :raise"
      end
      @mode = value
    end

    # Set a callback for :notify mode
    def on_violation=(callback)
      unless callback.respond_to?(:call)
        raise ArgumentError, "on_violation must be callable"
      end
      @on_violation = callback
    end

    # Check if a budget exists for the given key
    def budget_for(key)
      normalized = normalize_key(key)
      @rules[normalized]
    end

    # Check stats against budget and return violations
    def check(key, stats)
      budget = budget_for(key)
      return [] unless budget

      violations = []

      if budget[:count] && stats[:count] > budget[:count]
        violations << {
          type: :budget_exceeded_count,
          key: key,
          actual: stats[:count],
          limit: budget[:count]
        }
      end

      if budget[:duration_ms] && stats[:total_duration_ms] > budget[:duration_ms]
        violations << {
          type: :budget_exceeded_duration,
          key: key,
          actual: stats[:total_duration_ms],
          limit: budget[:duration_ms]
        }
      end

      violations
    end

    # Enforce budget violations according to current mode
    def enforce!(key, violations)
      return if violations.empty?

      case @mode
      when :log
        log_violations(key, violations)
      when :notify
        notify_violations(key, violations)
      when :raise
        raise_violations(key, violations)
      end
    end

    private

    def normalize_key(key)
      key.to_s.downcase.gsub(/\s+/, "")
    end

    def log_violations(key, violations)
      violations.each do |v|
        message = format_violation(key, v)
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.warn("[QueryGuard::Budget] #{message}")
        else
          warn("[QueryGuard::Budget] #{message}")
        end
      end
    end

    def notify_violations(key, violations)
      return unless @on_violation

      violations.each do |v|
        @on_violation.call(key, v)
      end
    end

    def raise_violations(key, violations)
      messages = violations.map { |v| format_violation(key, v) }
      raise Violation, messages.join("; ")
    end

    def format_violation(key, v)
      case v[:type]
      when :budget_exceeded_count
        "#{key}: Query count exceeded (#{v[:actual]} > #{v[:limit]})"
      when :budget_exceeded_duration
        "#{key}: Total duration exceeded (#{v[:actual].round(2)}ms > #{v[:limit]}ms)"
      else
        "#{key}: #{v[:type]}"
      end
    end
  end
end
