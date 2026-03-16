# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Migrations::MigrationAnalyzer do
  let(:analyzer) { described_class.new }
  let(:fixture_migrations_dir) { File.expand_path("../fixture_migrations", __FILE__) }

  describe "#analyze_migration" do
    it "detects unsafe add_index without concurrently" do
      migration_file = File.join(fixture_migrations_dir, "20240101000001_create_users_table.rb")
      findings = analyzer.analyze_migration(migration_file)

      # Should find 2 unsafe indexes
      index_findings = findings.select { |f| f.rule_name == :index_not_concurrent }
      expect(index_findings.count).to eq(2)
      
      expect(index_findings.first.severity).to eq(:error)
      expect(index_findings.first.title).to include("Index Addition Without CONCURRENTLY")
      expect(index_findings.first.message).to include("add_index without algorithm: :concurrently")
    end

    it "detects non-null column without default" do
      migration_file = File.join(fixture_migrations_dir, "20240102000001_add_status_to_users.rb")
      findings = analyzer.analyze_migration(migration_file)

      non_null_findings = findings.select { |f| f.rule_name == :non_null_no_default }
      expect(non_null_findings).not_to be_empty
      
      finding = non_null_findings.first
      expect(finding.severity).to eq(:error)
      expect(finding.title).to include("Non-NULL Column Without Default")
    end

    it "detects column type changes" do
      migration_file = File.join(fixture_migrations_dir, "20240103000001_change_email_type_on_users.rb")
      findings = analyzer.analyze_migration(migration_file)

      change_findings = findings.select { |f| f.rule_name == :change_column_lock }
      expect(change_findings).not_to be_empty
      
      finding = change_findings.first
      expect(finding.severity).to eq(:error)
      expect(finding.title).to include("Column Type Change Locks Table")
      expect(finding.metadata[:operation]).to eq("change_column")
    end

    it "detects full-table updates" do
      migration_file = File.join(fixture_migrations_dir, "20240104000001_populate_status_on_users.rb")
      findings = analyzer.analyze_migration(migration_file)

      update_findings = findings.select { |f| f.rule_name == :full_table_update }
      expect(update_findings).not_to be_empty
      
      finding = update_findings.first
      expect(finding.severity).to eq(:error)
      expect(finding.title).to include("Full-Table Update in Migration")
      expect(finding.metadata[:operation]).to eq("update_all")
    end

    it "detects dangerous raw SQL" do
      migration_file = File.join(fixture_migrations_dir, "20240105000001_migrate_old_data.rb")
      findings = analyzer.analyze_migration(migration_file)

      sql_findings = findings.select { |f| f.rule_name == :dangerous_raw_sql }
      expect(sql_findings.count).to be >= 2  # TRUNCATE and potentially DELETE
      
      dangerous = sql_findings.first
      expect(dangerous.severity).to eq(:error)
      expect(dangerous.title).to include("Dangerous Raw SQL")
    end

    it "detects remove_column operations" do
      migration_file = File.join(fixture_migrations_dir, "20240106000001_remove_and_rename_columns.rb")
      findings = analyzer.analyze_migration(migration_file)

      remove_findings = findings.select { |f| f.rule_name == :remove_column_lock }
      expect(remove_findings).not_to be_empty
      
      finding = remove_findings.first
      expect(finding.severity).to eq(:error)
      expect(finding.title).to include("Column Removal Locks Table")
    end

    it "detects rename_column operations" do
      migration_file = File.join(fixture_migrations_dir, "20240106000001_remove_and_rename_columns.rb")
      findings = analyzer.analyze_migration(migration_file)

      rename_findings = findings.select { |f| f.rule_name == :rename_column_lock }
      expect(rename_findings).not_to be_empty
      
      finding = rename_findings.first
      expect(finding.severity).to eq(:warn)
      expect(finding.title).to include("Column Rename Locks Table")
    end

    it "does not flag safe concurrent index addition" do
      migration_file = File.join(fixture_migrations_dir, "20240107000001_add_index_concurrently_to_users.rb")
      findings = analyzer.analyze_migration(migration_file)

      # Safe migration should have no findings
      expect(findings).to be_empty
    end

    it "does not flag safe column addition with default" do
      migration_file = File.join(fixture_migrations_dir, "20240108000001_add_default_status_to_users.rb")
      findings = analyzer.analyze_migration(migration_file)

      # Safe migration should have no findings
      expect(findings).to be_empty
    end

    it "returns empty array for non-existent file" do
      findings = analyzer.analyze_migration("/nonexistent/path/migration.rb")
      expect(findings).to be_empty
    end

    it "includes file_path in findings" do
      migration_file = File.join(fixture_migrations_dir, "20240101000001_create_users_table.rb")
      findings = analyzer.analyze_migration(migration_file)

      expect(findings).not_to be_empty
      findings.each do |finding|
        expect(finding.file_path).to eq(migration_file)
      end
    end

    it "includes line numbers in findings" do
      migration_file = File.join(fixture_migrations_dir, "20240101000001_create_users_table.rb")
      findings = analyzer.analyze_migration(migration_file)

      expect(findings).not_to be_empty
      findings.each do |finding|
        expect(finding.line_number).to be > 0
      end
    end

    it "includes recommendations in findings" do
      migration_file = File.join(fixture_migrations_dir, "20240101000001_create_users_table.rb")
      findings = analyzer.analyze_migration(migration_file)

      expect(findings).not_to be_empty
      findings.each do |finding|
        expect(finding.recommendations).not_to be_empty
        expect(finding.recommendations.first).to be_a(String)
      end
    end

    it "includes metadata in findings" do
      migration_file = File.join(fixture_migrations_dir, "20240101000001_create_users_table.rb")
      findings = analyzer.analyze_migration(migration_file)

      expect(findings).not_to be_empty
      findings.each do |finding|
        expect(finding.metadata).to be_a(Hash)
        expect(finding.metadata[:operation]).not_to be_nil
        expect(finding.metadata[:risk_level]).not_to be_nil
      end
    end
  end

  describe "#analyze_migrations_directory" do
    it "analyzes all migration files in directory" do
      findings = analyzer.analyze_migrations_directory(fixture_migrations_dir)

      # Should find multiple issues across all test migrations
      expect(findings.count).to be > 0
    end

    it "includes findings from all migrations" do
      findings = analyzer.analyze_migrations_directory(fixture_migrations_dir)

      # Check for diverse finding types
      finding_types = findings.map(&:rule_name).uniq
      expect(finding_types.count).to be > 1
    end

    it "returns empty array for non-existent directory" do
      findings = analyzer.analyze_migrations_directory("/nonexistent/migrations")
      expect(findings).to be_empty
    end

    it "only processes .rb files" do
      findings = analyzer.analyze_migrations_directory(fixture_migrations_dir)
      
      expect(findings).not_to be_empty
      # All findings should have file_path ending in .rb
      findings.each do |finding|
        expect(finding.file_path).to end_with(".rb")
      end
    end
  end

  describe "#analyze (integration with context)" do
    it "integrates with QueryGuard context" do
      config = QueryGuard::Config.new
      config.migrations_directory = fixture_migrations_dir
      
      context = QueryGuard::Core::Context.new
      
      findings = analyzer.analyze(context, config)
      
      expect(findings.count).to be > 0
      expect(findings.all? { |f| f.analyzer_name == :migration_risk }).to be true
    end

    it "respects disabled_analyzers configuration" do
      config = QueryGuard::Config.new
      config.migrations_directory = fixture_migrations_dir
      config.disable_analyzer(:migration_risk)
      
      context = QueryGuard::Core::Context.new
      
      # After disabling, should not run analysis
      expect(analyzer.enabled?(config)).to be false
    end
  end

  describe "Finding structure" do
    it "creates properly structured findings" do
      migration_file = File.join(fixture_migrations_dir, "20240101000001_create_users_table.rb")
      findings = analyzer.analyze_migration(migration_file)

      finding = findings.first
      expect(finding).to be_a(QueryGuard::Core::Finding)
      expect(finding.analyzer_name).to eq(:migration_risk)
      expect(finding.rule_name).not_to be_nil
      expect(finding.severity).to be_in(QueryGuard::Core::Finding::SEVERITIES)
      expect(finding.title).not_to be_empty
      expect(finding.description).not_to be_empty
      expect(finding.message).not_to be_empty
    end

    it "severity matches risk level" do
      migration_file = File.join(fixture_migrations_dir, "20240102000001_add_status_to_users.rb")
      findings = analyzer.analyze_migration(migration_file)

      # High-risk migration should have error severity
      expect(findings.all? { |f| f.severity == :error }).to be true
    end

    it "includes recommended actions" do
      migration_file = File.join(fixture_migrations_dir, "20240101000001_create_users_table.rb")
      findings = analyzer.analyze_migration(migration_file)

      expect(findings).not_to be_empty
      findings.each do |finding|
        expect(finding.recommendations.first).to include_any(
          "algorithm: :concurrently",
          "Provide a default",
          "Create new column",
          "separate migration"
        )
      end
    end
  end

  describe "Edge cases" do
    it "handles migrations with multiple issues" do
      migration_file = File.join(fixture_migrations_dir, "20240106000001_remove_and_rename_columns.rb")
      findings = analyzer.analyze_migration(migration_file)

      # Should find both remove_column and rename_column issues
      expect(findings.count).to be >= 2
    end

    it "handles migrations with mixed safe and unsafe operations" do
      # If a migration has both safe and unsafe operations, 
      # should only report unsafe ones
      findings = analyzer.analyze_migrations_directory(fixture_migrations_dir)
      
      # Safe migrations should not appear in findings
      safe_migration_counts = findings.select do |f|
        f.file_path.include?("add_default") || f.file_path.include?("add_index_concurrently")
      end.count
      
      expect(safe_migration_counts).to eq(0)
    end

    it "handles migrations with no database changes" do
      # Create a migration that does nothing
      temp_file = File.join(fixture_migrations_dir, "test_empty_migration.rb")
      File.write(temp_file, 'class EmptyMigration < ActiveRecord::Migration[6.0]; end')
      
      findings = analyzer.analyze_migration(temp_file)
      expect(findings).to be_empty
      
      File.delete(temp_file)
    end
  end
end
