# frozen_string_literal: true
require "active_support"
require "active_support/notifications"
require "query_guard/version"
require "query_guard/core/query"
require "query_guard/core/finding"
require "query_guard/core/finding_builders"
require "query_guard/core/context"
require "query_guard/analysis/risk_level"
require "query_guard/analysis/risk_detectors"
require "query_guard/analysis/query_risk_classifier"
require "query_guard/explain/adapter_interface"
require "query_guard/explain/postgresql_adapter"
require "query_guard/explain/plan_signals"
require "query_guard/suggest/pattern_extractors"
require "query_guard/suggest/index_suggester"
require "query_guard/explain/explain_enricher"
require "query_guard/analyzers/base"
require "query_guard/analyzers/registry"
require "query_guard/analyzers/slow_query_analyzer"
require "query_guard/analyzers/query_count_analyzer"
require "query_guard/analyzers/select_star_analyzer"
require "query_guard/analyzers/query_risk_analyzer"
require "query_guard/migrations/migration_risk_detectors"
require "query_guard/migrations/migration_analyzer"
require "query_guard/migrations/database_adapter"
require "query_guard/migrations/postgresql_adapter"
require "query_guard/migrations/table_size_resolver"
require "query_guard/migrations/table_risk_analyzer"
require "query_guard/budget"
require "query_guard/fingerprint"
require "query_guard/trace"
require "query_guard/config"
require "query_guard/store"
require "query_guard/security"
require "query_guard/subscriber"
require "query_guard/action_controller_subscriber"
require "query_guard/middleware"
require "query_guard/client"
require "query_guard/uploader/interface"
require "query_guard/uploader/no_op_uploader"
require "query_guard/uploader/http_uploader"
require "query_guard/uploader/registry"
require "query_guard/uploader/upload_service"
require "query_guard/cli/source_metadata_collector"
require "query_guard/cli/json_reporter"
require "query_guard/cli/batch_report_formatter"
require "query_guard/cli/paged_report_formatter"
require "query_guard/cli/formatter"
require "query_guard/cli/command"

module QueryGuard
  class << self
    attr_accessor :client

    def config
      @config ||= Config.new
    end

    def configure
      yield(config)
      @client = Client.new(
        base_url: config.base_url,
        api_key:  config.api_key,
        project:  config.project,
        env:      config.env
      )
      self
    end

    def install!(app = nil)
      config
      Subscriber.install!(config)
      ActionControllerSubscriber.install!(config)

      if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
        Rails.application.config.middleware.use(QueryGuard::Middleware, config)
      elsif app
        app.use(QueryGuard::Middleware, config)
      end

      self
    end

    def exporter
      @exporter ||= QueryGuard::Exporter.new(config)
    end

    # Trace a block of code and capture query stats.
    # Returns [result, report] tuple.
    def trace(label, context: {}, &block)
      Trace.trace(label, context: context, &block)
    end
  end
end

if defined?(Rails::Railtie)
  module QueryGuard
    class Railtie < Rails::Railtie
      initializer "query_guard.install" do |app|
        QueryGuard.install!(app)
      end
    end
  end
end
