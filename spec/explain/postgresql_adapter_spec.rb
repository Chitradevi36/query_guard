# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Explain::PostgreSQLAdapter do
  let(:mock_connection) { MockPostgreSQLConnection.new }
  let(:adapter) { described_class.new(mock_connection) }

  # Mock PostgreSQL connection that simulates responses
  class MockPostgreSQLConnection
    def initialize
      @responses = {}
    end

    def execute(sql)
      if sql.include?("EXPLAIN")
        result = MockResult.new(SAMPLE_EXPLAIN_SEQUENTIAL_SCAN)
        result
      else
        MockResult.new("OK")
      end
    end

    def set_response_for(sql, json_response)
      @responses[sql] = json_response
    end

    class MockResult
      def initialize(data)
        @data = data
      end

      def rows
        [[JSON.pretty_generate(@data)]]
      end
    end
  end

  # Sample EXPLAIN outputs for different scenarios
  SAMPLE_EXPLAIN_SEQUENTIAL_SCAN = {
    "Plan" => {
      "Node Type" => "Seq Scan",
      "Relation Name" => "users",
      "Plans" => [],
      "Estimated Rows" => 1000,
      "Total Cost" => 35.50
    },
    "Planning Time" => 0.234,
    "Execution Time" => 2.543
  }.freeze

  SAMPLE_EXPLAIN_INDEX_SCAN = {
    "Plan" => {
      "Node Type" => "Index Scan",
      "Relation Name" => "users",
      "Index Name" => "idx_users_email",
      "Plans" => [],
      "Estimated Rows" => 1,
      "Total Cost" => 0.42
    },
    "Planning Time" => 0.123,
    "Execution Time" => 0.045
  }.freeze

  SAMPLE_EXPLAIN_WITH_ANALYZE = {
    "Plan" => {
      "Node Type" => "Seq Scan",
      "Relation Name" => "users",
      "Plans" => [],
      "Estimated Rows" => 1000,
      "Actual Rows" => 1250,
      "Total Cost" => 35.50,
      "Actual Total Time" => 15.234
    },
    "Planning Time" => 0.234,
    "Execution Time" => 15.234,
    "Triggers" => []
  }.freeze

  describe "#initialize" do
    it "stores connection" do
      expect(adapter.instance_variable_get(:@connection)).to eq(mock_connection)
    end

    it "sets default timeout" do
      expect(adapter.instance_variable_get(:@timeout)).to eq(5.0)
    end

    it "allows custom timeout" do
      custom_adapter = described_class.new(mock_connection, timeout: 10.0)
      expect(custom_adapter.instance_variable_get(:@timeout)).to eq(10.0)
    end

    it "defaults use_analyze to false" do
      expect(adapter.instance_variable_get(:@use_analyze)).to be false
    end
  end

  describe "#engine_name" do
    it "returns :postgresql" do
      expect(adapter.engine_name).to eq(:postgresql)
    end
  end

  describe "#can_explain?" do
    it "allows SELECT queries" do
      expect(adapter.can_explain?("SELECT * FROM users")).to be true
    end

    it "allows WHERE clauses" do
      expect(adapter.can_explain?("SELECT id FROM users WHERE status = 'active'")).to be true
    end

    it "allows CTEs" do
      expect(adapter.can_explain?("WITH user_list AS (SELECT id FROM users) SELECT * FROM user_list")).to be true
    end

    it "rejects PRAGMA queries" do
      expect(adapter.can_explain?("PRAGMA table_info(users)")).to be false
    end

    it "rejects transaction control" do
      expect(adapter.can_explain?("BEGIN")).to be false
      expect(adapter.can_explain?("COMMIT")).to be false
    end

    it "rejects DDL queries" do
      expect(adapter.can_explain?("DROP TABLE users")).to be false
      expect(adapter.can_explain?("ALTER TABLE users ADD COLUMN age INT")).to be false
      expect(adapter.can_explain?("CREATE TABLE users (id INT)")).to be false
      expect(adapter.can_explain?("TRUNCATE TABLE users")).to be false
    end

    it "rejects UPDATE/DELETE with RETURNING" do
      expect(adapter.can_explain?("UPDATE users SET active = true RETURNING id")).to be false
      expect(adapter.can_explain?("DELETE FROM users WHERE id = 1 RETURNING id")).to be false
    end
  end

  describe "#get_plan" do
    it "returns parsed EXPLAIN output" do
      plan = adapter.get_plan("SELECT * FROM users")
      expect(plan).to be_a(Hash)
      expect(plan["Plan"]).to be_present
    end

    it "extracts planning time" do
      plan = adapter.get_plan("SELECT * FROM users")
      expect(plan["Planning Time"]).to eq(0.234)
    end

    it "extracts execution time" do
      plan = adapter.get_plan("SELECT * FROM users")
      expect(plan["Execution Time"]).to eq(2.543)
    end

    it "extracts plan root node" do
      plan = adapter.get_plan("SELECT * FROM users")
      root = plan["Plan"]
      expect(root["Node Type"]).to eq("Seq Scan")
      expect(root["Relation Name"]).to eq("users")
    end

    it "raises UnsupportedQueryError for dangerous queries" do
      expect { adapter.get_plan("DROP TABLE users") }.to raise_error(
        QueryGuard::Explain::UnsupportedQueryError
      )
    end

    it "raises AdapterError on parse failure" do
      # Mock connection that returns invalid JSON
      bad_connection = MockPostgreSQLConnection.new
      bad_connection.define_singleton_method(:execute) do |_sql|
        class BadResult
          def rows
            [["not valid json"]]
          end
        end
        BadResult.new
      end

      bad_adapter = described_class.new(bad_connection)
      expect { bad_adapter.get_plan("SELECT * FROM users") }.to raise_error(
        QueryGuard::Explain::AdapterError,
        /Failed to parse EXPLAIN/
      )
    end
  end

  describe "#build_explain_query" do
    it "builds basic EXPLAIN query" do
      sql = adapter.send(:build_explain_query, "SELECT * FROM users", false)
      expect(sql).to include("EXPLAIN")
      expect(sql).to include("FORMAT JSON")
      expect(sql).not_to include("ANALYZE")
    end

    it "includes ANALYZE when requested" do
      sql = adapter.send(:build_explain_query, "SELECT * FROM users", true)
      expect(sql).to include("ANALYZE")
      expect(sql).to include("BUFFERS")
    end

    it "preserves original query" do
      original = "SELECT id FROM users WHERE status = 'active'"
      sql = adapter.send(:build_explain_query, original, false)
      expect(sql).to include(original)
    end
  end

  describe "different EXPLAIN scenarios" do
    it "parses sequential scan plans" do
      plan = adapter.get_plan("SELECT * FROM users")
      expect(plan["Plan"]["Node Type"]).to eq("Seq Scan")
    end

    it "parses index scan plans" do
      adapter.define_singleton_method(:execute_query_with_timeout) do |sql|
        [
          [JSON.pretty_generate(SAMPLE_EXPLAIN_INDEX_SCAN)]
        ]
      end

      plan = adapter.get_plan("SELECT * FROM users WHERE email = 'test@example.com'")
      expect(plan["Plan"]["Node Type"]).to eq("Index Scan")
      expect(plan["Plan"]["Index Name"]).to eq("idx_users_email")
    end

    it "parses ANALYZE output with actual metrics" do
      adapter.define_singleton_method(:execute_query_with_timeout) do |sql|
        [
          [JSON.pretty_generate(SAMPLE_EXPLAIN_WITH_ANALYZE)]
        ]
      end

      plan = adapter.get_plan("SELECT * FROM users", use_analyze: true)
      expect(plan["Plan"]["Actual Rows"]).to eq(1250)
      expect(plan["Plan"]["Actual Total Time"]).to eq(15.234)
    end
  end

  describe "logging support" do
    let(:logger) { instance_double(Logger) }
    let(:adapter_with_logger) { described_class.new(mock_connection, logger: logger, validate_connection: false) }

    it "logs debug messages when logger is provided" do
      expect(logger).to receive(:debug).at_least(:once).with(/PostgreSQLAdapter/)

      adapter_with_logger.get_plan("SELECT * FROM users")
    end

    it "does not raise when logger is nil" do
      adapter_no_logger = described_class.new(mock_connection, validate_connection: false)
      expect { adapter_no_logger.get_plan("SELECT * FROM users") }.not_to raise_error
    end

    it "logs warnings on unsupported queries" do
      expect(logger).to receive(:warn).with(/Cannot EXPLAIN this query type/)

      expect { adapter_with_logger.get_plan("DROP TABLE users") }
        .to raise_error(QueryGuard::Explain::UnsupportedQueryError)
    end
  end

  describe "connection validation" do
    it "validates connection on initialization by default" do
      mock_valid_connection = instance_double(MockPostgreSQLConnection)
      expect(mock_valid_connection).to receive(:execute).and_return(
        MockPostgreSQLConnection::MockResult.new("SELECT version()" => "PostgreSQL 13.0")
      )

      adapter_validation = described_class.new(mock_valid_connection, validate_connection: true)
      expect(adapter_validation).not_to be_nil
    end

    it "skips validation when validate_connection is false" do
      mock_conn = instance_double(MockPostgreSQLConnection)
      expect(mock_conn).not_to receive(:execute).with(/version/)

      adapter_no_validation = described_class.new(mock_conn, validate_connection: false)
      expect(adapter_no_validation).not_to be_nil
    end

    it "raises ConnectionError if validation fails" do
      bad_connection = instance_double(MockPostgreSQLConnection)
      allow(bad_connection).to receive(:execute).and_raise(StandardError, "Connection refused")

      expect {
        described_class.new(bad_connection, validate_connection: true)
      }.to raise_error(QueryGuard::Explain::ConnectionError, /Cannot validate/)
    end
  end

  describe "error handling" do
    it "raises PlanParseError for invalid JSON" do
      bad_connection = MockPostgreSQLConnection.new
      bad_connection.define_singleton_method(:execute) do |_sql|
        class BadResult
          def rows
            [["not valid json"]]
          end
        end
        BadResult.new
      end

      bad_adapter = described_class.new(bad_connection, validate_connection: false)
      expect { bad_adapter.get_plan("SELECT * FROM users") }
        .to raise_error(QueryGuard::Explain::PlanParseError)
    end

    it "raises TimeoutError when query times out" do
      timeout_adapter = described_class.new(mock_connection, timeout: 0.001, validate_connection: false)
      timeout_adapter.define_singleton_method(:execute_query_with_timeout) do |_sql|
        raise Timeout::Error, "Execution timed out"
      end

      expect { timeout_adapter.get_plan("SELECT * FROM huge_table") }
        .to raise_error(QueryGuard::Explain::TimeoutError, /timed out/)
    end

    it "raises AdapterError with context when execution fails" do
      bad_adapter = described_class.new(mock_connection, validate_connection: false)
      bad_adapter.define_singleton_method(:execute_query_with_timeout) do |_sql|
        raise StandardError, "Connection lost"
      end

      expect { bad_adapter.get_plan("SELECT * FROM users") }
        .to raise_error(QueryGuard::Explain::AdapterError)
    end
  end
end
