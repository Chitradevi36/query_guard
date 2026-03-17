# Rule 2: algorithm: :concurrently WITHOUT disable_ddl_transaction!
# This is RISKY - will cause transaction error in PostgreSQL

class RiskyConcurrentIndexNoDdlTransaction < ActiveRecord::Migration[6.0]
  def change
    # ERROR: This requires disable_ddl_transaction! to work
    add_index :users, :email, algorithm: :concurrently
  end
end
