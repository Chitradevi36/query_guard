# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Migrations::MigrationRiskDetectors do
  describe "6 Migration Safety Rules" do
    let(:fixture_dir) { File.expand_path("../../fixtures/migrations", __FILE__) }

    # Rule 1: add_index without algorithm: :concurrently
    describe "Rule 1: add_index without algorithm: :concurrently" do
      it "detects risky index additions" do
        content = File.read("#{fixture_dir}/20240101000001_risky_index_add.rb")
        risks = described_class.detect_risks(content, "RiskyIndexAdd")

        expect(risks).not_to be_empty
        expect(risks.map { |r| r[:type] }).to include(:index_not_concurrent)
        expect(risks.find { |r| r[:type] == :index_not_concurrent }[:severity]).to eq(:error)
      end

      it "passes for indexes with algorithm: :concurrently" do
        content = File.read("#{fixture_dir}/20240101000002_safe_index_add.rb")
        risks = described_class.detect_risks(content, "SafeIndexAdd")

        concurrent_risks = risks.select { |r| r[:type] == :index_not_concurrent }
        expect(concurrent_risks).to be_empty
      end
    end

    # Rule 2: algorithm: :concurrently without disable_ddl_transaction!
    describe "Rule 2: algorithm: :concurrently without disable_ddl_transaction!" do
      it "detects concurrent index without disable_ddl_transaction!" do
        content = File.read("#{fixture_dir}/20240101000003_risky_concurrent_no_ddl.rb")
        risks = described_class.detect_risks(content, "RiskyConcurrentIndexNoDdlTransaction")

        expect(risks).not_to be_empty
        expect(risks.map { |r| r[:type] }).to include(:concurrent_index_no_disable_ddl)
        expect(risks.find { |r| r[:type] == :concurrent_index_no_disable_ddl }[:severity]).to eq(:error)
      end

      it "passes when disable_ddl_transaction! is present" do
        content = File.read("#{fixture_dir}/20240101000002_safe_index_add.rb")
        risks = described_class.detect_risks(content, "SafeIndexAdd")

        concurrent_risks = risks.select { |r| r[:type] == :concurrent_index_no_disable_ddl }
        expect(concurrent_risks).to be_empty
      end
    end

    # Rule 3: add_column with null: false on existing table
    describe "Rule 3: add_column with null: false without default" do
      it "detects non-null column additions without defaults" do
        content = File.read("#{fixture_dir}/20240101000004_risky_add_not_null.rb")
        risks = described_class.detect_risks(content, "RiskyAddNotNullColumn")

        expect(risks).not_to be_empty
        expect(risks.map { |r| r[:type] }).to include(:non_null_no_default)
        expect(risks.find { |r| r[:type] == :non_null_no_default }[:severity]).to eq(:error)
      end

      it "passes when default value is provided" do
        content = File.read("#{fixture_dir}/20240101000005_safe_add_not_null.rb")
        risks = described_class.detect_risks(content, "SafeAddNotNullColumn")

        null_risks = risks.select { |r| r[:type] == :non_null_no_default }
        expect(null_risks).to be_empty
      end
    end

    # Rule 4: change_column on existing table
    describe "Rule 4: change_column on existing table" do
      it "detects change_column operations" do
        content = File.read("#{fixture_dir}/20240101000006_risky_change_column.rb")
        risks = described_class.detect_risks(content, "RiskyChangeColumn")

        expect(risks).not_to be_empty
        expect(risks.map { |r| r[:type] }).to include(:change_column_lock)
        expect(risks.find { |r| r[:type] == :change_column_lock }[:severity]).to eq(:error)
      end

      it "passes for safe schema-only changes" do
        content = File.read("#{fixture_dir}/20240101000007_safe_change_column.rb")
        risks = described_class.detect_risks(content, "SafeChangeColumn")

        change_risks = risks.select { |r| r[:type] == :change_column_lock }
        expect(change_risks).to be_empty
      end
    end

    # Rule 5: raw SQL via execute (dangerous statements)
    describe "Rule 5: Dangerous raw SQL via execute" do
      it "detects TRUNCATE operations" do
        content = File.read("#{fixture_dir}/20240101000008_risky_raw_sql.rb")
        risks = described_class.detect_risks(content, "RiskyRawSql")

        truncate_risks = risks.select { |r| r[:type] == :dangerous_raw_sql && r[:message].include?("TRUNCATE") }
        expect(truncate_risks).not_to be_empty
        expect(truncate_risks.first[:severity]).to eq(:error)
      end

      it "detects DROP operations" do
        content = File.read("#{fixture_dir}/20240101000008_risky_raw_sql.rb")
        risks = described_class.detect_risks(content, "RiskyRawSql")

        drop_risks = risks.select { |r| r[:type] == :dangerous_raw_sql && r[:message].include?("DROP") }
        expect(drop_risks).not_to be_empty
      end

      it "detects UPDATE without WHERE clause" do
        content = File.read("#{fixture_dir}/20240101000008_risky_raw_sql.rb")
        risks = described_class.detect_risks(content, "RiskyRawSql")

        full_update_risks = risks.select { |r| r[:type] == :unsafe_raw_sql_full_table }
        expect(full_update_risks).not_to be_empty
      end

      it "passes for safe SQL with WHERE clause" do
        content = File.read("#{fixture_dir}/20240101000009_safe_raw_sql.rb")
        risks = described_class.detect_risks(content, "SafeRawSql")

        dangerous_risks = risks.select { |r| r[:type] == :dangerous_raw_sql }
        expect(dangerous_risks).to be_empty
      end
    end

    # Rule 6: data backfill / app-model usage in migrations
    describe "Rule 6: Data backfill using app models in migrations" do
      it "detects find_each usage in migrations" do
        content = File.read("#{fixture_dir}/20240101000010_risky_data_backfill.rb")
        risks = described_class.detect_risks(content, "RiskyDataBackfill")

        expect(risks).not_to be_empty
        expect(risks.map { |r| r[:type] }).to include(:data_backfill_in_migration)
      end

      it "detects Model.update_all in migrations" do
        content = File.read("#{fixture_dir}/20240101000010_risky_data_backfill.rb")
        risks = described_class.detect_risks(content, "RiskyDataBackfill")

        backfill_risks = risks.select { |r| r[:type] == :data_backfill_in_migration }
        expect(backfill_risks).not_to be_empty
      end

      it "detects Model.delete_all in migrations" do
        content = File.read("#{fixture_dir}/20240101000010_risky_data_backfill.rb")
        risks = described_class.detect_risks(content, "RiskyDataBackfill")

        backfill_risks = risks.select { |r| r[:type] == :data_backfill_in_migration }
        expect(backfill_risks.count).to be >= 3  # find_each + update_all + delete_all
      end

      it "passes for schema-only migrations" do
        content = File.read("#{fixture_dir}/20240101000011_safe_data_backfill.rb")
        risks = described_class.detect_risks(content, "SafeDataBackfill")

        backfill_risks = risks.select { |r| r[:type] == :data_backfill_in_migration }
        expect(backfill_risks).to be_empty
      end
    end
  end

  describe "Finding structure" do
    let(:migration_content) do
      <<~RUBY
        class TestMigration < ActiveRecord::Migration[6.0]
          def change
            add_index :users, :email
          end
        end
      RUBY
    end

    it "includes all required finding attributes" do
      risks = described_class.detect_risks(migration_content, "TestMigration")

      expect(risks.first).to include(
        :type,
        :severity,
        :line_number,
        :migration_name,
        :title,
        :description,
        :message,
        :recommendation,
        :metadata
      )
    end

    it "has structured metadata" do
      risks = described_class.detect_risks(migration_content, "TestMigration")
      metadata = risks.first[:metadata]

      expect(metadata).to include(:operation, :risk_level)
    end

    it "provides actionable recommendations" do
      risks = described_class.detect_risks(migration_content, "TestMigration")

      expect(risks.first[:recommendation]).not_to be_empty
      expect(risks.first[:recommendation]).to match(/algorithm: :concurrently/)
    end
  end

  describe "Edge cases and false positives" do
    it "ignores commented-out risky operations" do
      content = <<~RUBY
        class TestMigration < ActiveRecord::Migration[6.0]
          def change
            # add_index :users, :email
            # User.find_each { |u| u.update(slug: u.name) }
          end
        end
      RUBY

      risks = described_class.detect_risks(content, "TestMigration")

      # Should have no risky operations flagged (commented code)
      index_risks = risks.select { |r| r[:type] == :index_not_concurrent }
      expect(index_risks).to be_empty
    end

    it "does not flag Date/Time/Array classes as models" do
      content = <<~RUBY
        class TestMigration < ActiveRecord::Migration[6.0]
          def change
            add_column :events, :starts_at, :datetime
            # Safe to use built-in classes
            puts Date.today
            Array.new(10)
          end
        end
      RUBY

      risks = described_class.detect_risks(content, "TestMigration")
      backfill_risks = risks.select { |r| r[:type] == :data_backfill_in_migration }

      expect(backfill_risks).to be_empty
    end

    it "handles multiline index definitions" do
      content = <<~RUBY
        class TestMigration < ActiveRecord::Migration[6.0]
          def change
            add_index :users, 
                      :email,
                      unique: true
          end
        end
      RUBY

      risks = described_class.detect_risks(content, "TestMigration")
      index_risks = risks.select { |r| r[:type] == :index_not_concurrent }

      expect(index_risks).not_to be_empty
    end
  end
end
