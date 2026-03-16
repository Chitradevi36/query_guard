# frozen_string_literal: true
require "active_support/notifications"

module QueryGuard
  module ActionControllerSubscriber
    EVENT = "unpermitted_parameters.action_controller"

    def self.install!(config)
      return if @installed
      @subscriber = ActiveSupport::Notifications.subscribe(EVENT) do |_name, _start, _finish, _id, payload|
        stats = Thread.current[:query_guard_stats]
        next unless stats
        next unless config.enable_security && config.detect_mass_assignment

        keys = Array(payload[:keys]).map(&:to_s)
        sensitive = keys & Array(config.sensitive_param_keys)

        stats[:violations] << {
          type: :mass_assignment_unpermitted_params,
          keys: keys.take(50),
          sensitive_keys: sensitive.take(50)
        }
      end
      @installed = true
    end
  end
end
