# frozen_string_literal: true

module QueryGuard
  module Migrations
    # Extracts table names from Rails migration code
    #
    # Pragmatically identifies which tables a migration affects
    # by parsing common Rails migration method calls.
    #
    # Detects: add_column, remove_column, change_column, create_table, drop_table,
    # etc. on both active table operations and raw SQL.
    class TableSizeResolver
      # Extract all table names referenced in a migration
      #
      # @param migration_content [String] Migration file content
      # @return [Array<String>] Table names (deduplicated)
      def self.extract_table_names(migration_content)
        tables = Set.new

        lines = migration_content.lines

        lines.each do |line|
          next if line.strip.start_with?("#")
          next if line.strip.empty?

          # Try to capture table name: could be :symbol or "string" or 'string'
          # add_column :users, :name, :string
          if line.include?("add_column")
            # Match: add_column :table_name or add_column "table_name" or add_column 'table_name'
            if match = line.match(/add_column\s+[:"`']?(\w+)/)
              tables << match[1]
            end
          end

          # remove_column :posts, :old_field
          if line.include?("remove_column")
            if match = line.match(/remove_column\s+[:"`']?(\w+)/)
              tables << match[1]
            end
          end

          # change_column :users, :email, :text
          if line.include?("change_column")
            if match = line.match(/change_column\s+[:"`']?(\w+)/)
              tables << match[1]
            end
          end

          # rename_column :users, :old_name, :new_name
          if line.include?("rename_column")
            if match = line.match(/rename_column\s+[:"`']?(\w+)/)
              tables << match[1]
            end
          end

          # add_index :users, :email
          if line.include?("add_index")
            if match = line.match(/add_index\s+[:"`']?(\w+)/)
              tables << match[1]
            end
          end

          # remove_index :users, :email
          if line.include?("remove_index")
            if match = line.match(/remove_index\s+[:"`']?(\w+)/)
              tables << match[1]
            end
          end

          # drop_table :posts
          if line.include?("drop_table")
            if match = line.match(/drop_table\s+[:"`']?(\w+)/)
              tables << match[1]
            end
          end

          # create_table :accounts do ... end
          if line.include?("create_table")
            if match = line.match(/create_table\s+[:"`']?(\w+)/)
              tables << match[1]
            end
          end

          # Raw SQL UPDATE public.users SET ...
          if line.upcase.include?("UPDATE")
            if match = line.match(/UPDATE\s+(?:public\.)?(\w+)/i)
              tables << match[1]
            end
          end

          # Raw SQL DELETE FROM public.users
          if line.upcase.include?("DELETE")
            if match = line.match(/DELETE\s+FROM\s+(?:public\.)?(\w+)/i)
              tables << match[1]
            end
          end

          # Raw SQL INSERT INTO public.users
          if line.upcase.include?("INSERT")
            if match = line.match(/INSERT\s+INTO\s+(?:public\.)?(\w+)/i)
              tables << match[1]
            end
          end

          # Model.update_all(status: 'active') - convert model to table name
          # or User.delete_all
          if (line.include?("update_all") || line.include?("delete_all"))
            if match = line.match(/(\b[A-Z]\w*)\s*\.\s*(?:update_all|delete_all)/)
              model_name = match[1]
              # Convert CamelCase to snake_case: User -> user, UserProfile -> user_profile
              table_name = model_name
                .gsub(/([A-Z])/, '_\1')
                .downcase
                .sub(/^_/, '')
              # Pluralize simple table names: add 's' for most words
              # This is a simple heuristic; full pluralization would require a library
              table_name = table_name + 's' unless table_name.end_with?('s', 'x', 'z')
              tables << table_name if table_name && !table_name.empty?
            end
          end
        end

        tables.to_a.sort
      end

      # Filter tables to only those likely affected by schema changes
      #
      # Excludes internal Rails tables like schema_migrations
      #
      # @param table_names [Array<String>] List of table names
      # @return [Array<String>] Filtered list
      def self.filter_schema_tables(table_names)
        # Internal rails tables to ignore
        internal_tables = %w[
          schema_migrations ar_internal_metadata
          delayed_jobs sidekiq_jobs
        ]

        table_names.reject { |name| internal_tables.include?(name) }
      end

      # Extract table names that schema changes would directly affect
      #
      # @param migration_content [String] Migration file content
      # @return [Array<String>] Directly affected tables
      def self.affected_tables(migration_content)
        all_tables = extract_table_names(migration_content)
        filter_schema_tables(all_tables)
      end
    end
  end
end
