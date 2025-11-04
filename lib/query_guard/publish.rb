# frozen_string_literal: true
require "time"
require_relative "client"

module QueryGuard
  class << self
    def client
      @client ||= Client.new(
        base_url: (config.api_base_url || ENV["QUERYGUARD_API_URL"] || "http://localhost:4000"),
        api_key:  (config.api_key      || ENV["QUERYGUARD_API_KEY"]),
        project:  (config.project      || ENV["QUERYGUARD_PROJECT"] || "dev"),
        env:      (config.env          || (defined?(Rails) ? Rails.env : "development"))
      )
    end

    # thread-local queue for the current request
    def buffer; Thread.current[:qg_buf] ||= [] end
    def clear!; Thread.current[:qg_buf]  = []  end

    def track!(attrs)
      return unless enabled?
      buffer << default_fields.merge(attrs)
    end

    def flush_now!
      return if buffer.empty?
      client.post("/api/v1/events", { events: buffer.dup })
    ensure
      clear!
    end

    private

    def default_fields
      { occurred_at: Time.now.utc.iso8601 }
    end
  end
end
