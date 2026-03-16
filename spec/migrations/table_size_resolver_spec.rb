# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Migrations::TableSizeResolver do
  describe "#extract_table_names" do
    it "extracts tables from add_column" do
      migration = <<~RUBY
        class AddNameToUsers < ActiveRecord::Migration[6.0]
          def change
            add_column :users, :name, :string
          end
        end
      RUBY

      tables = described_class.extract_table_names(migration)

      expect(tables).to include("users")
    end

    it "extracts tables from remove_column" do
      migration = <<~RUBY
        def change
          remove_column :posts, :old_field
        end
      RUBY

      tables = described_class.extract_table_names(migration)

      expect(tables).to include("posts")
    end

    it "extracts tables from change_column" do
      migration = <<~RUBY
        def change
          change_column :products, :price, :decimal
        end
      RUBY

      tables = described_class.extract_table_names(migration)

      expect(tables).to include("products")
    end

    it "extracts tables from create_table" do
      migration = <<~RUBY
        def change
          create_table :accounts do |t|
            t.string :name
            t.timestamps
          end
        end
      RUBY

      tables = described_class.extract_table_names(migration)

      expect(tables).to include("accounts")
    end

    it "extracts tables from raw SQL UPDATE" do
      migration = <<~RUBY
        def change
          execute("UPDATE users SET status = 'active'")
        end
      RUBY

      tables = described_class.extract_table_names(migration)

      expect(tables).to include("users")
    end

    it "extracts tables from raw SQL DELETE" do
      migration = <<~RUBY
        def change
          execute("DELETE FROM orders WHERE created_at < NOW() - interval '1 year'")
        end
      RUBY

      tables = described_class.extract_table_names(migration)

      expect(tables).to include("orders")
    end

    it "extracts tables from add_index" do
      migration = <<~RUBY
        def change
          add_index :users, :email
        end
      RUBY

      tables = described_class.extract_table_names(migration)

      expect(tables).to include("users")
    end

    it "extracts tables from Model.update_all" do
      migration = <<~RUBY
        def change
          User.update_all(status: "active")
        end
      RUBY

      tables = described_class.extract_table_names(migration)

      expect(tables).to include("users")
    end

    it "extracts tables from Model.delete_all" do
      migration = <<~RUBY
        def change
          Comment.delete_all
        end
      RUBY

      tables = described_class.extract_table_names(migration)

      expect(tables).to include("comments")
    end

    it "handles multiple tables" do
      migration = <<~RUBY
        def change
          add_column :users, :name, :string
          remove_column :posts, :old_field
          add_index :comments, :user_id
        end
      RUBY

      tables = described_class.extract_table_names(migration)

      expect(tables).to include("users", "posts", "comments")
    end

    it "ignores commented lines" do
      migration = <<~RUBY
        def change
          # add_index :ignored_table, :id
          add_column :users, :name, :string
        end
      RUBY

      tables = described_class.extract_table_names(migration)

      expect(tables).not_to include("ignored_table")
      expect(tables).to include("users")
    end

    it "ignores empty lines" do
      migration = <<~RUBY
        def change

          add_column :users, :name, :string

        end
      RUBY

      tables = described_class.extract_table_names(migration)

      expect(tables).to include("users")
    end

    it "deduplicates table names" do
      migration = <<~RUBY
        def change
          add_column :users, :name, :string
          add_column :users, :email, :string
          add_index :users, :email
        end
      RUBY

      tables = described_class.extract_table_names(migration)

      # Should have users only once
      expect(tables.count).to eq(1)
      expect(tables).to include("users")
    end

    it "handles quoted table names" do
      migration = <<~RUBY
        def change
          add_column "users", :name, :string
          create_table 'products' do |t|
            t.string :title
          end
        end
      RUBY

      tables = described_class.extract_table_names(migration)

      expect(tables).to include("users", "products")
    end

    it "handles public schema prefix in SQL" do
      migration = <<~RUBY
        def change
          execute("UPDATE public.users SET status = 'active'")
        end
      RUBY

      tables = described_class.extract_table_names(migration)

      expect(tables).to include("users")
    end
  end

  describe "#filter_schema_tables" do
    it "removes internal Rails tables" do
      tables = ["users", "posts", "schema_migrations", "ar_internal_metadata"]

      filtered = described_class.filter_schema_tables(tables)

      expect(filtered).to include("users", "posts")
      expect(filtered).not_to include("schema_migrations", "ar_internal_metadata")
    end

    it "preserves user tables" do
      tables = ["users", "posts", "comments", "likes"]

      filtered = described_class.filter_schema_tables(tables)

      expect(filtered).to match_array(["users", "posts", "comments", "likes"])
    end

    it "removes common internal tables" do
      tables = ["users", "delayed_jobs", "sidekiq_jobs"]

      filtered = described_class.filter_schema_tables(tables)

      expect(filtered).to eq(["users"])
    end
  end

  describe "#affected_tables" do
    it "combines extraction and filtering" do
      migration = <<~RUBY
        def change
          add_column :users, :name, :string
          execute("UPDATE schema_migrations SET success = true")
        end
      RUBY

      tables = described_class.affected_tables(migration)

      expect(tables).to include("users")
      expect(tables).not_to include("schema_migrations")
    end

    it "returns empty array for migrations with no user tables" do
      migration = <<~RUBY
        def change
          # Just some comments
        end
      RUBY

      tables = described_class.affected_tables(migration)

      expect(tables).to be_empty
    end

    it "returns empty array for migrations only affecting internal tables" do
      migration = <<~RUBY
        def change
          execute("UPDATE ar_internal_metadata SET value = 'test'")
        end
      RUBY

      tables = described_class.affected_tables(migration)

      expect(tables).to be_empty
    end
  end
end
