# frozen_string_literal: true
require "securerandom"
require "query_guard/security"

module QueryGuard
  class Error < StandardError; end

  class Middleware
    class BodyProxy
      def initialize(body, stats)
        @body = body
        @stats = stats
      end

      def each
        @body.each do |chunk|
          @stats[:response_bytes] += chunk.to_s.bytesize
          yield chunk
        end
      end

      def close
        @body.close if @body.respond_to?(:close)
      end
    end

    def initialize(app, config)
      @app = app
      @config = config
    end

    def call(env)
      return @app.call(env) unless @config.enabled?(rails_env)

      # Initialize new Context for this request
      context = Core::Context.new
      Thread.current[:query_guard_context] = context
      
      # Legacy: Also initialize old stats hash for backward compatibility
      Thread.current[:query_guard_stats] = { 
        count: 0, 
        total_duration_ms: 0.0, 
        violations: [],
        response_bytes: 0 
      }

      status, headers, body = @app.call(env)
      
      # Wrap body to track response bytes
      proxied_body = BodyProxy.new(body, Thread.current[:query_guard_stats])
      
      # Run all registered analyzers
      findings = @config.analyzer_registry.analyze(context, @config)
      
      # Check and report findings
      check_and_report!(context, findings)
      
      [status, headers, proxied_body]
    ensure
      Thread.current[:query_guard_context] = nil
      Thread.current[:query_guard_stats] = nil
    end

    private

    def rails_env
      if defined?(Rails) && Rails.respond_to?(:env)
        Rails.env.to_sym
      else
        (ENV["RACK_ENV"] || ENV["APP_ENV"] || "development").to_sym
      end
    end

    def logger
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger
      else
        @logger ||= Logger.new($stdout)
      end
    end

    def check_and_report!(context, findings)
      # Check findings and legacy stats for backward compatibility
      stats = Thread.current[:query_guard_stats] || { count: 0, violations: [] }
      legacy_violations = stats[:violations].dup

      return if findings.empty? && legacy_violations.empty?

      # Log all findings
      findings.each do |finding|
        message = format_finding_message(finding)
        logger.warn(message)
      end

      # Log legacy violations for compatibility
      legacy_violations.each do |v|
        message = format_legacy_message(v, stats)
        logger.warn(message)
      end

      # Raise if configured
      if @config.raise_on_violation && (!findings.empty? || !legacy_violations.empty?)
        message = format_summary_message(findings, stats)
        raise QueryGuard::Error, message
      end
    end

    def format_finding_message(finding)
      "#{@config.log_prefix} [#{finding.severity.upcase}] #{finding.analyzer_name}:#{finding.rule_name} - #{finding.message}"
    end

    def format_legacy_message(v, stats)
      details = case v[:type]
                when :too_many_queries
                  "too_many_queries: count=#{v[:count]} limit=#{v[:limit]}"
                when :slow_query
                  "slow_query: #{v[:duration_ms]}ms SQL=#{truncate_sql(v[:sql])}"
                when :select_star
                  "select_star: SQL=#{truncate_sql(v[:sql])}"
                else
                  v[:type].to_s
                end
      "#{@config.log_prefix} queries=#{stats[:count]} total_ms=#{stats[:total_duration_ms].round(2)} | #{details}"
    end

    def format_message(stats, violations)
      details = violations.map do |v|
        case v[:type]
        when :too_many_queries
          "too_many_queries: count=#{v[:count]} limit=#{v[:limit]}"
        when :slow_query
          "slow_query: #{v[:duration_ms]}ms SQL=#{truncate_sql(v[:sql])}"
        when :select_star
          "select_star: SQL=#{truncate_sql(v[:sql])}"
        when :sql_injection_suspected
          "sql_injection_suspected: SQL=#{truncate_sql(v[:sql])}"
        when :possible_data_exfiltration_query
          "possible_exfiltration_query: SQL=#{truncate_sql(v[:sql])}"
        when :data_exfiltration_large_response
          "data_exfiltration_large_response: bytes=#{v[:bytes]} limit=#{v[:limit]} path=#{v[:path]}"
        when :data_exfiltration_suspected_export
          "data_exfiltration_suspected_export: bytes=#{v[:bytes]} path=#{v[:path]}"
        when :unusual_query_rate
          "unusual_query_rate: actor=#{v[:actor]} per_min=#{v[:per_minute]} limit=#{v[:limit]}"
        when :unusual_query_variety
          "unusual_query_variety: actor=#{v[:actor]} uniq_fp_per_min=#{v[:unique_fingerprints_per_minute]} limit=#{v[:limit]}"
        when :mass_assignment_unpermitted_params
          "mass_assignment_unpermitted: keys=#{v[:keys].join(',')} sensitive=#{v[:sensitive_keys].join(',')}"
        else
          v[:type].to_s
        end
      end.join(" | ")

      "#{@config.log_prefix} queries=#{stats[:count]} total_ms=#{stats[:total_duration_ms].round(2)} resp_bytes=#{stats[:response_bytes]} | #{details}"
    end

    def format_summary_message(findings, stats)
      details = findings.map { |f| "#{f.analyzer_name}:#{f.rule_name}" }.join(", ")
      "#{@config.log_prefix} violations: #{details}"
    end

    def truncate_sql(sql, max = 200)
      sql.length > max ? "#{sql[0, max]}..." : sql
    end
  end
end
