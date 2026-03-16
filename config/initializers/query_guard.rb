QueryGuard.configure do |config|
  # Core configuration - migrations are always analyzed
  config.enabled_environments = %i[development test]
  
  # Optional: query metrics (disabled by default)
  # Uncomment if you want to track query counts and duration:
  # config.max_queries_per_request = 20
  # config.max_duration_ms_per_query = 100
end
