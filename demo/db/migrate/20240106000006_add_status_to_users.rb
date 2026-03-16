class AddStatusToUsers < ActiveRecord::Migration[6.0]
  def change
    # ⚠️  ISSUE: Adding a NOT NULL column without a default value
    # If the users table already has rows, this migration will fail
    # because there's no value for the new column on existing rows
    #
    # The correct approach would be:
    # add_column :users, :status, :string, default: 'active', null: false
    add_column :users, :status, :string, null: false
  end
end
