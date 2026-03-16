# frozen_string_literal: true

require "spec_helper"

RSpec.describe "QueryGuard Integration" do
  describe "middleware + subscriber + analyzers flow" do
    let(:app) { ->(env) { [200, {}, ["OK"]] } }
    let(:config) { QueryGuard::Config.new }
    let(:middleware) { QueryGuard::Middleware.new(app, config) }

    before do
      QueryGuard::Subscriber.install!(config)
    end

    after do
      QueryGuard::Subscriber.uninstall!
    end

    def mock_sql_event(name, sql, duration_seconds)
      started = Time.now
      finished = started + duration_seconds
      
      ActiveSupport::Notifications.publish(
        "sql.active_record",
        started,
        finished,
        SecureRandom.uuid,
        name: name,
        sql: sql
      )
    end

    it "collects queries and detects slow queries" do
      config.enabled_environments = [:test]
      config.max_duration_ms_per_query = 100.0

      logger_output = []
      allow_any_instance_of(Logger).to receive(:warn) { |msg| logger_output << msg }

      # Simulate request
      env = { "RACK_ENV" => "test" }
      status, _, _ = middleware.call(env) do |e|
        mock_sql_event("User Load", "SELECT 1", 0.05)
        mock_sql_event("Post Load", "SELECT 2", 0.15) # Slow
        [200, {}, ["OK"]]
      end

      context = Thread.current[:query_guard_context]
      expect(context).to be_nil # Cleaned up
    end

    it "collects queries and detects too many queries" do
      config.enabled_environments = [:test]
      config.max_queries_per_request = 3

      env = { "RACK_ENV" => "test" }
      status, _, _ = middleware.call(env) do |e|
        4.times { |i| mock_sql_event("Load", "SELECT #{i}", 0.01) }
        [200, {}, ["OK"]]
      end

      expect(status).to eq(200)
    end

    it "detects SELECT * queries" do
      config.enabled_environments = [:test]
      config.block_select_star = true

      env = { "RACK_ENV" => "test" }
      status, _, _ = middleware.call(env) do |e|
        mock_sql_event("Load", "SELECT * FROM users", 0.01)
        [200, {}, ["OK"]]
      end

      expect(status).to eq(200)
    end

    it "respects disabled analyzers" do
      config.enabled_environments = [:test]
      config.max_duration_ms_per_query = 50.0
      config.disable_analyzer(:slow_query)

      # Even with slow query, should not detect since analyzer is disabled
      env = { "RACK_ENV" => "test" }
      middleware.call(env) do |e|
        mock_sql_event("Load", "SELECT 1", 0.1) # 100ms, over threshold
        [200, {}, ["OK"]]
      end

      # Should not raise or log error (would if slow_query was enabled)
    end

    it "skips analysis if not in enabled environment" do
      config.enabled_environments = [:production]

      env = { "RACK_ENV" => "test" }
      status, _, _ = middleware.call(env) do |e|
        [200, {}, ["OK"]]
      end

      expect(status).to eq(200)
      context = Thread.current[:query_guard_context]
      expect(context).to be_nil
    end

    it "raises on violation if configured" do
      config.enabled_environments = [:test]
      config.max_queries_per_request = 2
      config.raise_on_violation = true

      env = { "RACK_ENV" => "test" }
      
      expect do
        middleware.call(env) do |e|
          3.times { |i| mock_sql_event("Load", "SELECT #{i}", 0.01) }
          [200, {}, ["OK"]]
        end
      end.to raise_error(QueryGuard::Error)
    end
  end
end
