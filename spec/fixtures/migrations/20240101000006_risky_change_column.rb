# Rule 4: change_column on existing table
# This is RISKY - rewrites entire table and locks it

class RiskyChangeColumn < ActiveRecord::Migration[6.0]
  def change
    # WARNING: This rewrites the entire table and causes extended lock
    change_column :users, :name, :text
    change_column :posts, :description, :string, limit: 500
  end
end
