# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "securerandom"
require "digest"

module QueryGuard
  class Exporter
    def initialize(config)
      @config = config
    end

    def enabled?
      @config.base_url && @config.api_key && @config.project
    end

    def export!(stats)
      return unless enabled?

      payload = build_payload(stats)
      return if payload[:events].empty?

      if @config.export_mode.to_sym == :async
        Thread.new { post(payload) }
      else
        post(payload)
      end
    end

    private

    def build_payload(stats)
      events = []

      # Query events
      if @config.export_queries.to_sym == :all
        stats.fetch(:queries, []).each do |q|
          events << {
            type: "query",
            statement: q[:sql],
            durationMs: q[:duration_ms],
            timestamp: q[:occurred_at],
            originApp: @config.origin_app,
            fingerprint: fingerprint(q[:sql]),
            metadata: stats[:request] || {}
          }
        end
      end

      # Threat events from violations
      stats.fetch(:violations, []).each do |v|
        events << violation_to_threat(v, stats)
      end

      {
        projectId: @config.project,
        events: events.compact
      }
    end

    def fingerprint(sql)
      # cheap “normalized” hash
      normalized = sql.to_s.gsub(/\s+/, " ").strip
      Digest::SHA1.hexdigest(normalized)
    end

    def violation_to_threat(v, stats)
      case v[:type]&.to_sym
      when :slow_query
        {
          type: "threat",
          severity: "medium",
          threatType: "SlowQuery",
          description: "Slow query #{v[:duration_ms]}ms",
          timestamp: Time.now.utc.iso8601,
          originApp: @config.origin_app,
          metadata: {
            sql: v[:sql],
            request: stats[:request] || {}
          }
        }
      when :select_star
        {
          type: "threat",
          severity: "low",
          threatType: "SelectStar",
          description: "SELECT * detected",
          timestamp: Time.now.utc.iso8601,
          originApp: @config.origin_app,
          metadata: {
            sql: v[:sql],
            request: stats[:request] || {}
          }
        }
      when :too_many_queries
        {
          type: "threat",
          severity: "high",
          threatType: "TooManyQueries",
          description: "Query count #{v[:count]} exceeded limit #{v[:limit]}",
          timestamp: Time.now.utc.iso8601,
          originApp: @config.origin_app,
          metadata: { request: stats[:request] || {} }
        }
      end
    end

    def post(payload)
      uri = URI.join(@config.base_url.to_s, "/api/v1/events")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      req = Net::HTTP::Post.new(uri.request_uri)
      req["Content-Type"] = "application/json"
      req["Authorization"] = "Bearer #{@config.api_key}"
      req.body = JSON.generate(payload)
      http.request(req)
    rescue => e
      # Don’t crash the app if monitoring fails
      warn "#{@config.log_prefix} export failed: #{e.class}: #{e.message}"
    end
  end
end
