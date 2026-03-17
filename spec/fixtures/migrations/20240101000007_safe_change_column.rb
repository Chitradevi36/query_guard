# Rule 4: Safer column type change (multi-step approach)
# This is SAFE - avoids table rewrite in a single transaction

class SafeChangeColumn < ActiveRecord::Migration[6.0]
  def change
    # Step 1: Add new column in parallel with old
    # (done in separate migration, this is just add_column which is checked separately)
    add_column :users, :name_new, :text

    # Real migration usually does:
    # 1. add_column with new type
    # 2. deploy code to use backfill/populate new column
    # 3. deploy code to write to new column
    # 4. backfill remaining old column values
    # 5. swap column names
    # 6. drop old column in safe way after validation
  end
end
