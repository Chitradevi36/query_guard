# frozen_string_literal: true

module QueryGuard
  module Migrations
    # Detects risky patterns in Rails migration files.
    # Uses pragmatic line-by-line analysis rather than complex regex.
    # Returns structured finding data for each detected risk.
    class MigrationRiskDetectors
      # Detects migration risks from file content
      def self.detect_risks(migration_content, migration_name)
        risks = []

        # Run all detectors
        risks.concat(detect_unsafe_index_additions(migration_content, migration_name))
        risks.concat(detect_table_locking_operations(migration_content, migration_name))
        risks.concat(detect_non_null_additions(migration_content, migration_name))
        risks.concat(detect_full_table_updates(migration_content, migration_name))
        risks.concat(detect_unsafe_raw_sql(migration_content, migration_name))

        risks
      end

      private

      # Detect index additions without algorithm: :concurrently or add_index without safe options
      def self.detect_unsafe_index_additions(content, migration_name)
        risks = []

        # Find all add_index occurrences
        lines = content.lines
        lines.each_with_index do |line, index|
          next unless line.include?("add_index")

          # Check if line includes algorithm: :concurrently
          unless line.include?("algorithm: :concurrently") || line.include?("algorithm: :concurrent")
            risks << {
              type: :index_not_concurrent,
              severity: :error,
              line_number: index + 1,
              migration_name: migration_name,
              title: "Index Addition Without CONCURRENTLY",
              description: "Adding an index locks the table. Use algorithm: :concurrently for PostgreSQL.",
              message: "add_index without algorithm: :concurrently",
              recommendation: "Add algorithm: :concurrently to allow concurrent queries during index creation",
              metadata: {
                operation: "add_index",
                risk_level: :high,
                locking: true
              }
            }
          end
        end

        risks
      end

      # Detect operations that lock the table: remove_column, change_column, rename_column
      def self.detect_table_locking_operations(content, migration_name)
        risks = []
        lines = content.lines

        lines.each_with_index do |line, index|
          next if line.strip.start_with?("#")
          next if line.strip.empty?

          # Check with word boundary to match method calls with or without parentheses
          case line
          when /\bremove_column\b/
            risks << {
              type: :remove_column_lock,
              severity: :error,
              line_number: index + 1,
              migration_name: migration_name,
              title: "Remove Column Locks Table",
              description: "Removing a column rewrites the entire table, causing extended lock.",
              message: "remove_column operation locks table",
              recommendation: "Use safe_remove_column from a migration-safe gem, or manually soft-delete the column first",
              metadata: { operation: "remove_column", risk_level: :high, locking: true }
            }
          when /\bchange_column\b/
            risks << {
              type: :change_column_lock,
              severity: :error,
              line_number: index + 1,
              migration_name: migration_name,
              title: "Change Column Locks Table",
              description: "Changing a column type rewrites the entire table, causing extended lock.",
              message: "change_column operation locks table",
              recommendation: "Create new column, migrate data with backfill, then drop old column in separate migration",
              metadata: { operation: "change_column", risk_level: :high, locking: true }
            }
          when /\brename_column\b/
            risks << {
              type: :rename_column_lock,
              severity: :warn,
              line_number: index + 1,
              migration_name: migration_name,
              title: "Rename Column Brief Lock",
              description: "Renaming a column briefly locks the table during metadata update.",
              message: "rename_column operation locks table briefly",
              recommendation: "Use with caution in large tables; consider aliasing instead",
              metadata: { operation: "rename_column", risk_level: :medium, locking: true }
            }
          end
        end

        risks
      end

      # Detect adding NOT NULL columns without safe rollout pattern
      def self.detect_non_null_additions(content, migration_name)
        risks = []
        lines = content.lines

        lines.each_with_index do |line, index|
          next unless line.include?("add_column")
          next if line.strip.start_with?("#")

          # Check for null: false without default
          if line.include?("null: false") && !line.include?("default:")
            risks << {
              type: :non_null_no_default,
              severity: :error,
              line_number: index + 1,
              migration_name: migration_name,
              title: "Non-NULL Column Without Default",
              description: "Adding a NOT NULL column without a default value will fail on populated tables.",
              message: "add_column null: false (no default)",
              recommendation: "Provide a default value, or add the column as nullable and backfill in separate step.",
              metadata: { operation: "add_column", risk_level: :high }
            }
          end
        end

        risks
      end

      # Detect full-table updates inside migrations
      def self.detect_full_table_updates(content, migration_name)
        risks = []
        lines = content.lines

        lines.each_with_index do |line, index|
          next if line.strip.start_with?("#")

          # Detect Model.update_all or delete_all calls
          if line.include?(".update_all") || line.include?(".delete_all")
            risks << {
              type: :full_table_update,
              severity: :error,
              line_number: index + 1,
              migration_name: migration_name,
              title: "Full-Table Update in Migration",
              description: "Updating all rows in a migration locks the table and is slow on large tables.",
              message: "update_all or delete_all in migration",
              recommendation: "Use a separate rake task or background job for large updates. Process rows in batches with pauses.",
              metadata: { operation: "updateall", risk_level: :high, locking: true }
            }
          end
        end

        risks
      end

      # Detect unsafe raw SQL statements
      def self.detect_unsafe_raw_sql(content, migration_name)
        risks = []
        lines = content.lines

        lines.each_with_index do |line, index|
          next if line.strip.start_with?("#")
          next if line.strip.empty?

          # Check for dangerous SQL keywords in quoted strings in execute() calls
          if line.include?("execute") && (line.include?('"') || line.include?("'"))
            # Extract the SQL string from the line
            sql_match = line.match(/"([^"]+)"|'([^']+)'/)
            if sql_match
              sql = sql_match[1] || sql_match[2]
              upcase_sql = sql.upcase

              if upcase_sql.include?("TRUNCATE")
                risks << {
                  type: :dangerous_raw_sql,
                  severity: :error,
                  line_number: index + 1,
                  migration_name: migration_name,
                  title: "TRUNCATE in Migration",
                  description: "TRUNCATE operations are dangerous and can cause data loss.",
                  message: "TRUNCATE detected in raw SQL",
                  recommendation: "Avoid TRUNCATE; use safer alternatives or manual database cleanup",
                  metadata: { operation: "raw_sql", risk_level: :critical }
                }
              elsif upcase_sql.include?("DROP")
                risks << {
                  type: :dangerous_raw_sql,
                  severity: :error,
                  line_number: index + 1,
                  migration_name: migration_name,
                  title: "DROP in Migration",
                  description: "DROP operations are dangerous and can cause data loss.",
                  message: "DROP detected in raw SQL",
                  recommendation: "Avoid DROP in migrations; use Rails schema helpers instead",
                  metadata: { operation: "raw_sql", risk_level: :critical }
                }
              elsif upcase_sql.include?("LOCK TABLE")
                risks << {
                  type: :explicit_table_lock,
                  severity: :warn,
                  line_number: index + 1,
                  migration_name: migration_name,
                  title: "Explicit Table Lock",
                  description: "Explicit LOCK TABLE statements block all table access.",
                  message: "LOCK TABLE detected in raw SQL",
                  recommendation: "Avoid explicit locks; let migrations handle locking implicitly",
                  metadata: { operation: "raw_sql", risk_level: :medium }
                }
              elsif (upcase_sql.include?("UPDATE") || upcase_sql.include?("DELETE")) && !upcase_sql.include?("WHERE")
                risks << {
                  type: :unsafe_raw_sql_full_table,
                  severity: :error,
                  line_number: index + 1,
                  migration_name: migration_name,
                  title: "Full Table SQL Without WHERE",
                  description: "UPDATE/DELETE without WHERE clause affects entire table.",
                  message: "Full table operation without WHERE clause",
                  recommendation: "Always include WHERE clause; batch operations for safety",
                  metadata: { operation: "raw_sql", risk_level: :critical }
                }
              end
            end
          end

          # Also check for dangerous keywords on their own line
          upcase_line = line.upcase

          if upcase_line.include?("TRUNCATE") && !line.strip.start_with?("#")
            # Skip if already reported from execute() parsing
            next if line.include?("execute")

            risks << {
              type: :dangerous_raw_sql,
              severity: :error,
              line_number: index + 1,
              migration_name: migration_name,
              title: "TRUNCATE in Migration",
              description: "TRUNCATE operations are dangerous and can cause data loss.",
              message: "TRUNCATE detected",
              recommendation: "Avoid TRUNCATE; use safer alternatives or manual database cleanup",
              metadata: { operation: "raw_sql", risk_level: :critical }
            }
          elsif upcase_line.include?("DROP TABLE") || upcase_line.include?("DROP COLUMN")
            next if line.include?("execute")

            risks << {
              type: :dangerous_raw_sql,
              severity: :error,
              line_number: index + 1,
              migration_name: migration_name,
              title: "DROP in Migration",
              description: "DROP operations are dangerous and can cause data loss.",
              message: "DROP detected",
              recommendation: "Avoid DROP in migrations; use Rails schema helpers instead",
              metadata: { operation: "raw_sql", risk_level: :critical }
            }
          elsif upcase_line.include?("LOCK TABLE")
            next if line.include?("execute")

            risks << {
              type: :explicit_table_lock,
              severity: :warn,
              line_number: index + 1,
              migration_name: migration_name,
              title: "Explicit Table Lock",
              description: "Explicit LOCK TABLE statements block all table access.",
              message: "LOCK TABLE detected",
              recommendation: "Avoid explicit locks; let migrations handle locking implicitly",
              metadata: { operation: "raw_sql", risk_level: :medium }
            }
          end
        end

        risks
      end
    end
  end
end
