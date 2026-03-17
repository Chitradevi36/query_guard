# Rule 1: add_index WITH algorithm: :concurrently
# This is SAFE - allows concurrent queries during index creation

class SafeIndexAdd < ActiveRecord::Migration[6.0]
  disable_ddl_transaction!

  def change
    # PostgreSQL allows concurrent queries during this operation
    add_index :users, :email, algorithm: :concurrently
    add_index :posts, [:user_id, :created_at], algorithm: :concurrently
  end
end
