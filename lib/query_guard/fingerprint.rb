# frozen_string_literal: true
require "digest"

module QueryGuard
  # SQL fingerprinting and statistics module.
  # Normalizes SQL queries and tracks per-fingerprint statistics.
  module Fingerprint
    class << self
      # Generate a stable fingerprint for a SQL query by:
      # - Normalizing whitespace
      # - Replacing string literals with ?
      # - Replacing numeric literals with ?
      # - Replacing IN (...) lists with IN (?)
      # Returns a SHA1 hash of the normalized query
      def generate(sql)
        normalized = normalize(sql)
        Digest::SHA1.hexdigest(normalized)
      end

      # Normalize SQL by removing all literals and standardizing whitespace
      def normalize(sql)
        s = sql.to_s.dup
        
        # Replace string literals (both single and double quotes)
        s.gsub!(/'(?:''|[^'])*'/, "?")
        s.gsub!(/"(?:""|[^"])*"/, "?")
        
        # Replace numeric literals (integers and floats)
        s.gsub!(/\b\d+\.?\d*\b/, "?")
        
        # Replace IN (...) with IN (?)
        s.gsub!(/IN\s*\([^)]+\)/i, "IN (?)")
        
        # Normalize whitespace
        s.gsub!(/\s+/, " ")
        
        s.strip.downcase
      end

      # Get or initialize the stats store for the current process
      def stats
        @stats ||= Hash.new do |h, fp|
          h[fp] = {
            count: 0,
            total_duration_ms: 0.0,
            min_duration_ms: Float::INFINITY,
            max_duration_ms: 0.0,
            first_seen_at: Time.now,
            last_seen_at: Time.now
          }
        end
      end

      # Record a query execution
      def record(sql, duration_ms)
        fp = generate(sql)
        stat = stats[fp]
        
        stat[:count] += 1
        stat[:total_duration_ms] += duration_ms
        stat[:min_duration_ms] = [stat[:min_duration_ms], duration_ms].min
        stat[:max_duration_ms] = [stat[:max_duration_ms], duration_ms].max
        stat[:last_seen_at] = Time.now
        
        fp
      end

      # Get stats for a specific fingerprint
      def stats_for(fingerprint)
        stats[fingerprint]
      end

      # Get all fingerprints sorted by frequency
      def top_by_count(limit = 10)
        stats.sort_by { |_fp, s| -s[:count] }.first(limit).to_h
      end

      # Get all fingerprints sorted by total duration
      def top_by_duration(limit = 10)
        stats.sort_by { |_fp, s| -s[:total_duration_ms] }.first(limit).to_h
      end

      # Get all fingerprints sorted by average duration
      def top_by_avg_duration(limit = 10)
        stats.sort_by { |_fp, s| 
          s[:count] > 0 ? -(s[:total_duration_ms] / s[:count]) : 0
        }.first(limit).to_h
      end

      # Reset all stats (useful for testing)
      def reset!
        @stats = nil
      end
    end
  end
end
