# frozen_string_literal: true
require "active_support"
require "active_support/notifications"
require "query_guard/version"
require "query_guard/config"
require "query_guard/subscriber"
require "query_guard/middleware"

module QueryGuard
  class << self
    attr_accessor :client, :config

    def config
      @config ||= Config.new
    end

    def configure
      yield config
      self
    end

    def configure
      config ||= Config.new
      yield(config)
      client = Client.new(
        base_url: config.base_url,
        api_key:  config.api_key,
        project:  config.project,
        env:      config.env
      )
    end

    def install!(app = nil)
      # Install SQL subscriber once
      Subscriber.install!(config)

      # Install middleware (Rails or Rack)
      if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
        # Use a Railtie-less insert for safety if called early
        Rails.application.config.middleware.use(QueryGuard::Middleware, config)
      elsif app
        app.use(QueryGuard::Middleware, config)
      end
      self
    end
  end
end

# Auto-install for Rails via Railtie
if defined?(Rails::Railtie)
  class QueryGuard::Railtie < Rails::Railtie
    initializer "query_guard.install" do |app|
      QueryGuard.install!(app)
    end
  end
end
