# frozen_string_literal: true

class AddDefaultStatusToUsers < ActiveRecord::Migration[6.0]
  def change
    # SAFE: Column with default value (no lock)
    add_column :users, :role, :string, default: "user"
  end
end
