# Rule 5: Dangerous raw SQL via execute
# This is RISKY - direct SQL execution without safeguards

class RiskyRawSql < ActiveRecord::Migration[6.0]
  def change
    # CRITICAL: Full table update without WHERE clause
    execute "UPDATE users SET status = 'active'"

    # CRITICAL: TRUNCATE operation (data loss!)
    execute "TRUNCATE TABLE audit_logs"

    # CRITICAL: DROP without safeguards
    execute "DROP TABLE old_data"
  end
end
