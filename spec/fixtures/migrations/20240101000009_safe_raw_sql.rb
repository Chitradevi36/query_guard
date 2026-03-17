# Rule 5: Safe raw SQL via execute
# This is SAFE - proper safeguards and query design

class SafeRawSql < ActiveRecord::Migration[6.0]
  def change
    # SAFE: Uses Rails helpers instead of raw SQL when possible
    User.where(status: nil).update_all(status: "active")

    # SAFE: SQL with WHERE clause and explanation
    execute "DELETE FROM raw_logs WHERE created_at < NOW() - INTERVAL '1 year'"
  end
end
