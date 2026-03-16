# frozen_string_literal: true

class MigrateOldData < ActiveRecord::Migration[6.0]
  def up
    # RISK: Full-table delete without WHERE
    execute("DELETE FROM users")
    
    # RISK: Dangerous raw SQL - TRUNCATE
    execute("TRUNCATE TABLE users")
  end

  def down
    # Not reversible
  end
end
