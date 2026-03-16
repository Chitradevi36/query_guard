class RemovePhoneFromUsers < ActiveRecord::Migration[6.0]
  def change
    # ⚠️  CRITICAL ISSUE: Removing a column without any backfill or data migration
    # This causes immediate, irreversible data loss
    # Users who had phone numbers stored will lose that data
    #
    # The correct approach would be:
    # 1. Add a new migration to archive the data first
    # 2. Update active code to stop using the column
    # 3. In a follow-up migration, remove the column
    remove_column :users, :phone
  end
end
