# frozen_string_literal: true

class AddIndexConcurrentlyToUsers < ActiveRecord::Migration[6.0]
  def change
    # SAFE: Uses algorithm: :concurrently
    add_index :users, :status, algorithm: :concurrently
  end
end
