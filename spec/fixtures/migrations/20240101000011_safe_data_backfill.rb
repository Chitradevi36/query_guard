# Rule 6: Safe: Schema-only migration, data backfill in separate task/job
# This is SAFE - separates schema changes from data migration

class SafeDataBackfill < ActiveRecord::Migration[6.0]
  # Note: This migration ONLY adds the schema
  # Data backfill happens in separate rake task or post-deploy job
  
  def change
    # Schema change only - no data manipulation
    add_column :users, :slug, :string, index: true

    # That's it! Data backfill is done via:
    # - A rake task: bin/rake db:backfill_user_slugs
    # - OR a post-deploy job
    # - OR live in code with safe batching patterns
    # See comments in this migration or docs for backfill strategy
  end
end
