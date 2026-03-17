# Rule 3: add_column with null: false AND default value
# This is SAFE - provides default for existing rows

class SafeAddNotNullColumn < ActiveRecord::Migration[6.0]
  def change
    # Safe: ALL existing rows get the default value
    add_column :users, :status, :string, null: false, default: "active"
    add_column :posts, :published, :boolean, null: false, default: false
  end
end
