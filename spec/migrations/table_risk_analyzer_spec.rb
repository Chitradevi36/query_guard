# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Migrations::TableRiskAnalyzer do
  let(:mock_adapter) { double("DatabaseAdapter") }
  let(:analyzer) { described_class.new(mock_adapter) }

  describe "#enhance_risks" do
    context "when adapter is not connected" do
      before do
        allow(mock_adapter).to receive(:connected?).and_return(false)
      end

      it "returns risks unchanged when adapter unavailable" do
        migration = "add_index :users, :email"
        risks = [
          {
            type: :index_not_concurrent,
            severity: :error,
            line_number: 1,
            metadata: { operation: "add_index" }
          }
        ]

        enhanced = analyzer.enhance_risks(migration, risks)

        expect(enhanced).to eq(risks)
      end
    end

    context "when adapter is connected" do
      before do
        allow(mock_adapter).to receive(:connected?).and_return(true)
      end

      it "adds table metadata to risks" do
        migration = "add_index :users, :email"
        risks = [
          {
            type: :index_not_concurrent,
            severity: :error,
            line_number: 1,
            migration_name: "test_migration",
            title: "Unsafe Index",
            description: "Index without concurrently",
            message: "add_index without algorithm: :concurrently",
            recommendation: "Add algorithm: :concurrently",
            metadata: { operation: "add_index" }
          }
        ]

        allow(mock_adapter).to receive(:estimate_table_rows).with("users").and_return(500_000)
        allow(mock_adapter).to receive(:estimate_lock_risk).with("users").and_return(:low)

        enhanced = analyzer.enhance_risks(migration, risks)

        expect(enhanced.first[:metadata][:table_name]).to eq("users")
        expect(enhanced.first[:metadata][:estimated_table_rows]).to eq(500_000)
        expect(enhanced.first[:metadata][:table_lock_risk]).to eq(:low)
      end

      it "escalates severity for large tables" do
        migration = "add_index :users, :email"
        risks = [
          {
            type: :index_not_concurrent,
            severity: :error,
            line_number: 1,
            migration_name: "test_migration",
            title: "Unsafe Index",
            description: "Index without concurrently",
            message: "add_index without algorithm: :concurrently",
            recommendation: "Add algorithm: :concurrently",
            metadata: { operation: "add_index" }
          }
        ]

        allow(mock_adapter).to receive(:estimate_table_rows).with("users").and_return(50_000_000)
        allow(mock_adapter).to receive(:estimate_lock_risk).with("users").and_return(:high)

        enhanced = analyzer.enhance_risks(migration, risks)

        expect(enhanced.first[:severity]).to eq(:critical)
        expect(enhanced.first[:metadata][:severity_escalated]).to be(true)
      end

      it "escalates WARN to ERROR for medium tables" do
        migration = "rename_column :users, :old_name, :new_name"
        risks = [
          {
            type: :rename_column_lock,
            severity: :warn,
            line_number: 1,
            migration_name: "test_migration",
            title: "Rename Column",
            description: "Renames column",
            message: "rename_column detected",
            recommendation: "Be careful",
            metadata: { operation: "rename_column" }
          }
        ]

        allow(mock_adapter).to receive(:estimate_table_rows).with("users").and_return(5_000_000)
        allow(mock_adapter).to receive(:estimate_lock_risk).with("users").and_return(:medium)

        enhanced = analyzer.enhance_risks(migration, risks)

        expect(enhanced.first[:severity]).to eq(:error)
        expect(enhanced.first[:metadata][:severity_escalated]).to be(true)
      end

      it "does not escalate when table not found" do
        migration = "add_column :orphaned_table, :field, :string"
        risks = [
          {
            type: :add_column_no_default,
            severity: :error,
            line_number: 1,
            migration_name: "test_migration",
            title: "Add Column",
            description: "No default",
            message: "add_column without default",
            recommendation: "Add default",
            metadata: { operation: "add_column" }
          }
        ]

        allow(mock_adapter).to receive(:estimate_table_rows).with("orphaned_table").and_return(nil)
        allow(mock_adapter).to receive(:estimate_lock_risk).with("orphaned_table").and_return(nil)

        enhanced = analyzer.enhance_risks(migration, risks)

        # Severity should not change
        expect(enhanced.first[:severity]).to eq(:error)
        expect(enhanced.first[:metadata][:table_lock_risk]).to be_nil
      end

      it "preserves original severity in metadata when escalating" do
        migration = "add_index :users, :email"
        risks = [
          {
            type: :index_not_concurrent,
            severity: :error,
            line_number: 1,
            migration_name: "test_migration",
            title: "Unsafe Index",
            description: "Index without concurrently",
            message: "add_index without algorithm: :concurrently",
            recommendation: "Add algorithm: :concurrently",
            metadata: { operation: "add_index" }
          }
        ]

        allow(mock_adapter).to receive(:estimate_table_rows).with("users").and_return(500_000_000)
        allow(mock_adapter).to receive(:estimate_lock_risk).with("users").and_return(:critical)

        enhanced = analyzer.enhance_risks(migration, risks)

        expect(enhanced.first[:metadata][:original_severity]).to eq(:error)
      end

      it "handles multiple risks on same table" do
        migration = <<~RUBY
          add_index :users, :email
          add_index :users, :username
        RUBY

        risks = [
          {
            type: :index_not_concurrent,
            severity: :error,
            line_number: 1,
            migration_name: "test_migration",
            title: "Unsafe Index 1",
            description: "Index without concurrently",
            message: "add_index without algorithm: :concurrently",
            recommendation: "Add algorithm: :concurrently",
            metadata: { operation: "add_index" }
          },
          {
            type: :index_not_concurrent,
            severity: :error,
            line_number: 2,
            migration_name: "test_migration",
            title: "Unsafe Index 2",
            description: "Index without concurrently",
            message: "add_index without algorithm: :concurrently",
            recommendation: "Add algorithm: :concurrently",
            metadata: { operation: "add_index" }
          }
        ]

        allow(mock_adapter).to receive(:estimate_table_rows).with("users").and_return(50_000_000)
        allow(mock_adapter).to receive(:estimate_lock_risk).with("users").and_return(:high)

        enhanced = analyzer.enhance_risks(migration, risks)

        expect(enhanced.length).to eq(2)
        enhanced.each do |risk|
          expect(risk[:metadata][:table_name]).to eq("users")
          expect(risk[:metadata][:estimated_table_rows]).to eq(50_000_000)
        end
      end
    end
  end

  describe "with NullDatabaseAdapter" do
    let(:analyzer) { described_class.new }

    it "works gracefully without database connection" do
      migration = "add_index :users, :email"
      risks = [
        {
          type: :index_not_concurrent,
          severity: :error,
          line_number: 1,
          migration_name: "test_migration",
          title: "Unsafe Index",
          description: "Index without concurrently",
          message: "add_index without algorithm: :concurrently",
          recommendation: "Add algorithm: :concurrently",
          metadata: { operation: "add_index" }
        }
      ]

      enhanced = analyzer.enhance_risks(migration, risks)

      # Should return risks unchanged
      expect(enhanced).to eq(risks)
    end
  end

  describe "lock risk escalation" do
    before do
      allow(mock_adapter).to receive(:connected?).and_return(true)
    end

    it "escalates error risks for high-risk tables" do
      risk = {
        type: :test_risk,
        severity: :error,
        metadata: {}
      }

      allow(mock_adapter).to receive(:estimate_table_rows).and_return(50_000_000)
      allow(mock_adapter).to receive(:estimate_lock_risk).and_return(:high)

      migration = "add_index :users, :email"
      enhanced = analyzer.enhance_risks(migration, [risk])

      expect(enhanced.first[:severity]).to eq(:critical)
    end

    it "escalates warn risks for medium-to-high tables" do
      risk = {
        type: :test_risk,
        severity: :warn,
        metadata: {}
      }

      allow(mock_adapter).to receive(:estimate_table_rows).and_return(500_000_000)
      allow(mock_adapter).to receive(:estimate_lock_risk).and_return(:critical)

      migration = "rename_column :users, :old, :new"
      enhanced = analyzer.enhance_risks(migration, [risk])

      expect(enhanced.first[:severity]).to eq(:error)
    end

    it "does not escalate :info severity" do
      risk = {
        type: :test_risk,
        severity: :info,
        metadata: {}
      }

      allow(mock_adapter).to receive(:estimate_table_rows).and_return(500_000_000)
      allow(mock_adapter).to receive(:estimate_lock_risk).and_return(:critical)

      migration = "add_index :users, :email"
      enhanced = analyzer.enhance_risks(migration, [risk])

      expect(enhanced.first[:severity]).to eq(:info)
    end
  end

  describe "row count formatting" do
    before do
      allow(mock_adapter).to receive(:connected?).and_return(true)
    end

    it "formats small counts" do
      migration = "add_index :users, :email"
      risks = [
        {
          type: :index_not_concurrent,
          severity: :error,
          line_number: 1,
          migration_name: "test",
          title: "Test",
          description: "Test",
          message: "test",
          recommendation: "test",
          metadata: {}
        }
      ]

      allow(mock_adapter).to receive(:estimate_table_rows).and_return(500)
      allow(mock_adapter).to receive(:estimate_lock_risk).and_return(:low)

      enhanced = analyzer.enhance_risks(migration, risks)

      expect(enhanced.first[:metadata][:escalation_reason]).to include("500 rows")
    end

    it "formats thousands" do
      migration = "add_index :users, :email"
      risks = [
        {
          type: :index_not_concurrent,
          severity: :error,
          line_number: 1,
          migration_name: "test",
          title: "Test",
          description: "Test",
          message: "test",
          recommendation: "test",
          metadata: {}
        }
      ]

      allow(mock_adapter).to receive(:estimate_table_rows).and_return(5_500_000)
      allow(mock_adapter).to receive(:estimate_lock_risk).and_return(:medium)

      enhanced = analyzer.enhance_risks(migration, risks)

      expect(enhanced.first[:metadata][:escalation_reason]).to include("5.5M rows")
    end
  end
end
