# frozen_string_literal: true
require "active_support"
require "active_support/cache"

module QueryGuard
  # Minimal store abstraction for rate counters.
  # Default: in-process MemoryStore. In production you can swap with Redis-based adapter.
  class Store
    def initialize(cache: nil)
      @cache = cache || ActiveSupport::Cache::MemoryStore.new(size: 8.megabytes)
    end

    # Increment integer key, expiring after ttl seconds
    def incr(key, ttl: 60, by: 1)
      val = (@cache.read(key) || 0).to_i + by
      @cache.write(key, val, expires_in: ttl)
      val
    end

    def read(key)
      @cache.read(key)
    end

    # "Set" emulation: store a Hash of members => true with ttl
    def add_to_set(key, member, ttl: 60)
      h = @cache.read(key)
      h = {} unless h.is_a?(Hash)
      h[member] = true
      @cache.write(key, h, expires_in: ttl)
      h.size
    end

    def set_size(key)
      h = @cache.read(key)
      h.is_a?(Hash) ? h.size : 0
    end
  end
end
