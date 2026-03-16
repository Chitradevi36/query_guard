# frozen_string_literal: true

class RemoveAndRenameColumns < ActiveRecord::Migration[6.0]
  def change
    # RISK: Column removal locks table
    remove_column :users, :name

    # RISK: Column rename locks table
    rename_column :users, :email, :user_email
  end
end
