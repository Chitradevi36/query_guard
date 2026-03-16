# frozen_string_literal: true

class PopulateStatusOnUsers < ActiveRecord::Migration[6.0]
  def change
    # RISK: Full-table update in migration
    User.update_all(status: "active")
  end
end
