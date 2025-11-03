# frozen_string_literal: true
require "active_support"
require "active_support/notifications"
require "query_guard/version"
require "query_guard/config"
require "query_guard/subscriber"
require "query_guard/middleware"
require "query_guard/client"

module QueryGuard
  class << self
    attr_accessor :client
    # Keep config as a normal module ivar; no mattr_*
    def config
      @config ||= Config.new
    end

    def configure
      yield(config)
      # Build a reusable HTTP client (whatever your Client class is)
      @client = Client.new(
        base_url: config.base_url,
        api_key:  config.api_key,
        project:  config.project,
        env:      config.env
      )
      self
    end

    def install!(app = nil)
      # Ensure config exists even if user didn't call configure
      config

      # Install SQL subscriber once
      Subscriber.install!(config)

      # Insert middleware
      if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
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
  module QueryGuard
    class Railtie < Rails::Railtie
      initializer "query_guard.install" do |app|
        QueryGuard.install!(app)
      end
    end
  end
end
