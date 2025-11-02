QueryGuard.configure do |c|
  c.enabled_environments      = %i[development test]  # Prod is usually off
  c.max_queries_per_request   = 100                   # nil to disable
  c.max_duration_ms_per_query = 100.0                 # nil to disable
  c.block_select_star         = false
  c.ignored_sql               = [/^PRAGMA /i, /^SAVEPOINT/i]
  c.raise_on_violation        = false                 # true to raise 500
  c.log_prefix                = "[QueryGuard]"
end
