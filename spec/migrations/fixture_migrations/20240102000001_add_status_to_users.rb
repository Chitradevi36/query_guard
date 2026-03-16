# frozen_string_literal: true

class AddStatusToUsers < ActiveRecord::Migration[6.0]
  def change
    # RISK: Non-NULL column without default
    add_column :users, :status, :string, null: false
  end
end
