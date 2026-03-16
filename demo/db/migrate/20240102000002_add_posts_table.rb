class AddPostsTable < ActiveRecord::Migration[6.0]
  def change
    create_table :posts do |t|
      t.references :user, foreign_key: true
      t.string :title
      t.text :content
      t.integer :view_count, default: 0

      t.timestamps
    end

    # Missing: add_index :posts, :user_id (already done by references, but no other indexes)
    # This will cause N+1 query problems when querying posts by user without index on content
  end
end
