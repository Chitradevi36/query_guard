# Rule 6: Data backfill using app models in migrations
# This is RISKY - models can change independently of migrations

class RiskyDataBackfill < ActiveRecord::Migration[6.0]
  def change
    # RISKY: Using ActiveRecord models in migration
    #  - Model code might change and break old migrations
    #  - find_each on 1M rows will lock table
    #  - If model has associations, N+1 queries happen
    
    add_column :users, :slug, :string

    User.find_each do |user|
      user.update_columns(slug: user.name.downcase.gsub(" ", "-"))
    end

    # Also risky: Model.update_all / delete_all
    Post.where(draft: true).update_all(status: "archived")
    Comment.where("created_at < ?", 1.year.ago).delete_all
  end
end
