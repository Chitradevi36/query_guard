# Rule 1: add_index without algorithm: :concurrently
# This is RISKY - will lock the table during index creation

class RiskyIndexAdd < ActiveRecord::Migration[6.0]
  def change
    # On large tables, this locks the table briefly
    add_index :users, :email
    add_index :posts, [:user_id, :created_at]
  end
end
