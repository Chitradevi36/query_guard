# frozen_string_literal: true
require "digest"

module QueryGuard
  module Security
    module_function

    # Normalize SQL into a stable fingerprint:
    # - collapse whitespace
    # - replace quoted strings + numbers with ?
    def fingerprint(sql)
      s = sql.to_s.dup
      s.gsub!(/\s+/, " ")
      s.gsub!(/'(?:''|[^'])*'/, "?") # strings
      s.gsub!(/\b\d+\b/, "?")        # integers
      Digest::SHA1.hexdigest(s.strip.downcase)
    end

    def suspicious_sql_injection?(sql, patterns)
      s = sql.to_s
      patterns.any? { |re| re.match?(s) }
    end

    def possible_exfiltration_query?(sql)
      s = sql.to_s.strip
      return false unless s =~ /\ASELECT\b/i
      # Heuristic: SELECT without WHERE and without LIMIT
      no_where = !s.match?(/\bwhere\b/i)
      no_limit = !s.match?(/\blimit\b/i)
      no_where && no_limit
    end

    def post_request_checks!(env, stats, config)
      return unless config.enable_security

      actor = resolve_actor(env, config)
      store = config.store || QueryGuard::Store.new

      # --- Unusual query pattern (rate/variety) ---
      if config.detect_unusual_query_pattern
        bucket = Time.now.utc.strftime("%Y%m%d%H%M") # minute bucket
        base = "qg:actor:#{actor}:#{bucket}"

        total = store.incr("#{base}:queries", ttl: 120, by: stats[:count].to_i)
        uniq_count = stats[:fingerprints]&.keys&.size.to_i
        store.add_to_set("#{base}:uniqfp", stats[:request_id], ttl: 120) # keep request marker

        uniq_fp_total = store.incr("#{base}:uniqfp_count", ttl: 120, by: uniq_count)

        if total > config.max_queries_per_minute_per_actor
          stats[:violations] << {
            type: :unusual_query_rate,
            actor: actor,
            per_minute: total,
            limit: config.max_queries_per_minute_per_actor
          }
        end

        if uniq_fp_total > config.max_unique_query_fingerprints_per_minute_per_actor
          stats[:violations] << {
            type: :unusual_query_variety,
            actor: actor,
            unique_fingerprints_per_minute: uniq_fp_total,
            limit: config.max_unique_query_fingerprints_per_minute_per_actor
          }
        end
      end

      # --- Data exfiltration (response size + endpoint hint) ---
      if config.detect_data_exfiltration
        bytes = stats[:response_bytes].to_i
        path  = env["PATH_INFO"].to_s

        if bytes > config.max_response_bytes_per_request
          stats[:violations] << {
            type: :data_exfiltration_large_response,
            bytes: bytes,
            limit: config.max_response_bytes_per_request,
            path: path
          }
        end

        if bytes > (config.max_response_bytes_per_request / 2) && path.match?(config.exfiltration_path_regex)
          stats[:violations] << {
            type: :data_exfiltration_suspected_export,
            bytes: bytes,
            path: path
          }
        end
      end
    end

    def resolve_actor(env, config)
      (config.actor_resolver && config.actor_resolver.call(env)) || "unknown"
    rescue
      "unknown"
    end
  end
end
