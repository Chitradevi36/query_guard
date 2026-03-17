# frozen_string_literal: true

class AddIndexConcurrentlyToUsers < ActiveRecord::Migration[6.0]
  disable_ddl_transaction!

  def change
    # SAFE: Uses algorithm: :concurrently with disable_ddl_transaction!
    add_index :users, :status, algorithm: :concurrently
  end
end
