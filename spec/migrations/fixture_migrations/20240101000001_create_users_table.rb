# frozen_string_literal: true

class CreateUsersTable < ActiveRecord::Migration[6.0]
  def change
    create_table :users do |t|
      t.string :email
      t.string :name
      t.timestamps
    end

    # RISK: index without algorithm: :concurrently
    add_index :users, :email
    add_index :users, :name
  end
end
