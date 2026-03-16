# frozen_string_literal: true

class ChangeEmailTypeOnUsers < ActiveRecord::Migration[6.0]
  def change
    # RISK: Type change locks table
    change_column :users, :email, :text
  end
end
