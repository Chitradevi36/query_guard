class AddIndexOnPostsContent < ActiveRecord::Migration[6.0]
  def change
    # ⚠️  ISSUE: Creating an index on a large table without CONCURRENTLY
    # On a table with millions of rows, this will lock the table
    # and cause downtime during the migration
    add_index :posts, :content

    # The correct way would be (PostgreSQL):
    # add_index :posts, :content, algorithm: :concurrently
  end
end
