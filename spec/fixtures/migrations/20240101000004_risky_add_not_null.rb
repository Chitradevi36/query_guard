# Rule 3: add_column with null: false on existing table
# This is RISKY - will fail if table already has rows

class RiskyAddNonNullColumn < ActiveRecord::Migration[6.0]
  def change
    # On a table with existing rows:
    # ERROR: Column "status" contains only null values
    add_column :users, :status, :string, null: false
    add_column :posts, :published, :boolean, null: false
  end
end
