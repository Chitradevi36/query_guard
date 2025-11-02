# frozen_string_literal: true
require "query_guard/version"
require "query_guard/config"
require "query_guard/subscriber"
require "query_guard/middleware"

module QueryGuard
  class << self
    def config
      @config ||= Config.new
    end

    def configure
      yield config
      self
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
