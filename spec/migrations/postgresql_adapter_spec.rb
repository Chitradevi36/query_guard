# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Migrations::PostgreSQLAdapter do
  let(:mock_connection) { double("ActiveRecord::Connection") }
  let(:adapter) { described_class.new(mock_connection) }

  describe "#estimate_table_rows" do
    it "returns row count from PostgreSQL statistics" do
      # Mock successful query result
      result = double("QueryResult")
      allow(result).to receive(:rows).and_return([[5_000_000]])

      allow(mock_connection).to receive(:exec_query).and_return(result)

      rows = adapter.estimate_table_rows(:users)

      expect(rows).to eq(5_000_000)
      expect(mock_connection).to have_received(:exec_query).once
    end

    it "returns nil when query fails" do
      allow(mock_connection).to receive(:exec_query)
        .and_raise(StandardError.new("Connection failed"))

      rows = adapter.estimate_table_rows(:users)

      expect(rows).to be_nil
    end

    it "returns nil when table not found" do
      result = double("QueryResult")
      allow(result).to receive(:rows).and_return([])

      allow(mock_connection).to receive(:exec_query).and_return(result)

      rows = adapter.estimate_table_rows(:nonexistent)

      expect(rows).to be_nil
    end

    it "caches results when cache enabled" do
      result = double("QueryResult")
      allow(result).to receive(:rows).and_return([[1_000_000]])

      allow(mock_connection).to receive(:exec_query).and_return(result)

      # First call
      adapter.estimate_table_rows(:users)

      # Second call should use cache
      adapter.estimate_table_rows(:users)

      # Should only query once
      expect(mock_connection).to have_received(:exec_query).once
    end

    it "does not cache when cache disabled" do
      adapter_no_cache = described_class.new(mock_connection, cache: false)

      result = double("QueryResult")
      allow(result).to receive(:rows).and_return([[1_000_000]])

      allow(mock_connection).to receive(:exec_query).and_return(result)

      adapter_no_cache.estimate_table_rows(:users)
      adapter_no_cache.estimate_table_rows(:users)

      # Should query twice
      expect(mock_connection).to have_received(:exec_query).twice
    end

    it "handles nil row count gracefully" do
      result = double("QueryResult")
      allow(result).to receive(:rows).and_return([[nil]])

      allow(mock_connection).to receive(:exec_query).and_return(result)

      rows = adapter.estimate_table_rows(:users)

      expect(rows).to be_nil
    end
  end

  describe "#estimate_lock_risk" do
    it "returns :low for small tables" do
      allow(adapter).to receive(:estimate_table_rows).and_return(500_000)

      risk = adapter.estimate_lock_risk(:users)

      expect(risk).to eq(:low)
    end

    it "returns :medium for 1M-10M row tables" do
      allow(adapter).to receive(:estimate_table_rows).and_return(5_000_000)

      risk = adapter.estimate_lock_risk(:users)

      expect(risk).to eq(:medium)
    end

    it "returns :high for 10M-100M row tables" do
      allow(adapter).to receive(:estimate_table_rows).and_return(50_000_000)

      risk = adapter.estimate_lock_risk(:users)

      expect(risk).to eq(:high)
    end

    it "returns :critical for tables > 100M rows" do
      allow(adapter).to receive(:estimate_table_rows).and_return(500_000_000)

      risk = adapter.estimate_lock_risk(:users)

      expect(risk).to eq(:critical)
    end

    it "returns nil when row count unavailable" do
      allow(adapter).to receive(:estimate_table_rows).and_return(nil)

      risk = adapter.estimate_lock_risk(:users)

      expect(risk).to be_nil
    end
  end

  describe "#table_exists?" do
    it "returns true when table exists" do
      result = double("QueryResult")
      allow(result).to receive(:rows).and_return([[1]])

      allow(mock_connection).to receive(:exec_query).and_return(result)

      exists = adapter.table_exists?(:users)

      expect(exists).to be(true)
    end

    it "returns false when table does not exist" do
      result = double("QueryResult")
      allow(result).to receive(:rows).and_return([])

      allow(mock_connection).to receive(:exec_query).and_return(result)

      exists = adapter.table_exists?(:nonexistent)

      expect(exists).to be(false)
    end

    it "returns false when query fails" do
      allow(mock_connection).to receive(:exec_query)
        .and_raise(StandardError.new("Connection error"))

      exists = adapter.table_exists?(:users)

      expect(exists).to be(false)
    end
  end

  describe "#list_tables" do
    it "returns list of tables in schema" do
      result = double("QueryResult")
      allow(result).to receive(:rows).and_return([["users"], ["posts"], ["comments"]])

      allow(mock_connection).to receive(:exec_query).and_return(result)

      tables = adapter.list_tables

      expect(tables).to eq(["users", "posts", "comments"])
    end

    it "returns empty array when schema is empty" do
      result = double("QueryResult")
      allow(result).to receive(:rows).and_return([])

      allow(mock_connection).to receive(:exec_query).and_return(result)

      tables = adapter.list_tables

      expect(tables).to be_empty
    end

    it "returns empty array when query fails" do
      allow(mock_connection).to receive(:exec_query)
        .and_raise(StandardError.new("Connection error"))

      tables = adapter.list_tables

      expect(tables).to be_empty
    end
  end

  describe "#connected?" do
    it "returns true when connection is healthy" do
      result = double("QueryResult")
      allow(mock_connection).to receive(:exec_query).and_return(result)

      connected = adapter.connected?

      expect(connected).to be(true)
    end

    it "returns false when connection fails" do
      allow(mock_connection).to receive(:exec_query)
        .and_raise(StandardError.new("Connection refused"))

      connected = adapter.connected?

      expect(connected).to be(false)
    end

    it "returns false when connection is nil" do
      adapter_no_conn = described_class.new(nil)

      connected = adapter_no_conn.connected?

      expect(connected).to be(false)
    end
  end

  describe "#clear_cache" do
    it "clears the row count cache" do
      result = double("QueryResult")
      allow(result).to receive(:rows).and_return([[1_000_000]])

      allow(mock_connection).to receive(:exec_query).and_return(result)

      # First call caches result
      adapter.estimate_table_rows(:users)

      # Clear cache
      adapter.clear_cache

      # Second call should query again
      adapter.estimate_table_rows(:users)

      expect(mock_connection).to have_received(:exec_query).twice
    end
  end

  describe "with custom schema" do
    it "queries specific schema" do
      custom_adapter = described_class.new(mock_connection, schema: "custom_schema")

      result = double("QueryResult")
      allow(result).to receive(:rows).and_return([[500_000]])

      allow(mock_connection).to receive(:exec_query).and_return(result)

      custom_adapter.estimate_table_rows(:users)

      # Verify schema parameter was passed
      expect(mock_connection).to have_received(:exec_query) do |sql, name, params|
        expect(params).to include(["custom_schema", :string])
      end
    end
  end
end

RSpec.describe QueryGuard::Migrations::NullDatabaseAdapter do
  let(:adapter) { described_class.new }

  it "always returns nil for estimate_table_rows" do
    expect(adapter.estimate_table_rows(:users)).to be_nil
  end

  it "always returns nil for estimate_lock_risk" do
    expect(adapter.estimate_lock_risk(:users)).to be_nil
  end

  it "always returns false for table_exists?" do
    expect(adapter.table_exists?(:users)).to be(false)
  end

  it "always returns empty array for list_tables" do
    expect(adapter.list_tables).to eq([])
  end

  it "always returns false for connected?" do
    expect(adapter.connected?).to be(false)
  end
end
