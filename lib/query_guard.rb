# frozen_string_literal: true
require "active_support"
require "active_support/notifications"
require "query_guard/version"
require "query_guard/config"
require "query_guard/store"
require "query_guard/security"
require "query_guard/subscriber"
require "query_guard/action_controller_subscriber"
require "query_guard/middleware"
require "query_guard/client"

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
