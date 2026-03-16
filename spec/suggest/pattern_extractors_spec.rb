# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Suggest::PatternExtractors do
  let(:extractor) { described_class.new }

  describe "#extract_where_columns" do
    it "extracts single equality condition" do
      sql = "SELECT * FROM users WHERE email = 'test@example.com'"
      expect(extractor.extract_where_columns(sql)).to eq(["email"])
    end

    it "extracts multiple equality conditions" do
      sql = "SELECT * FROM users WHERE email = 'test@example.com' AND status = 'active'"
      columns = extractor.extract_where_columns(sql)
      expect(columns).to include("email", "status")
    end

    it "extracts columns with comparison operators" do
      sql = "SELECT * FROM events WHERE created_at > '2024-01-01' AND priority >= 5"
      columns = extractor.extract_where_columns(sql)
      expect(columns).to include("created_at", "priority")
    end

    it "extracts columns from IN clause" do
      sql = "SELECT * FROM users WHERE id IN (1, 2, 3, 4)"
      expect(extractor.extract_where_columns(sql)).to eq(["id"])
    end

    it "extracts columns with LIKE operator" do
      sql = "SELECT * FROM users WHERE name LIKE 'John%'"
      expect(extractor.extract_where_columns(sql)).to eq(["name"])
    end

    it "handles case-insensitive WHERE keyword" do
      sql = "select * from users where email = 'test@example.com'"
      expect(extractor.extract_where_columns(sql)).to eq(["email"])
    end

    it "stops at GROUP BY clause" do
      sql = "SELECT status FROM users WHERE email = 'test@example.com' GROUP BY status"
      expect(extractor.extract_where_columns(sql)).to eq(["email"])
    end

    it "stops at ORDER BY clause" do
      sql = "SELECT * FROM users WHERE email = 'test@example.com' ORDER BY created_at"
      expect(extractor.extract_where_columns(sql)).to eq(["email"])
    end

    it "stops at LIMIT clause" do
      sql = "SELECT * FROM users WHERE email = 'test@example.com' LIMIT 10"
      expect(extractor.extract_where_columns(sql)).to eq(["email"])
    end

    it "returns empty array for no WHERE clause" do
      sql = "SELECT * FROM users"
      expect(extractor.extract_where_columns(sql)).to eq([])
    end

    it "returns empty array for nil input" do
      expect(extractor.extract_where_columns(nil)).to eq([])
    end

    it "returns empty array for empty string" do
      expect(extractor.extract_where_columns("")).to eq([])
    end

    it "handles multiple spaces and newlines" do
      sql = "SELECT * FROM users WHERE  email  =  'test@example.com'"
      expect(extractor.extract_where_columns(sql)).to eq(["email"])
    end

    it "avoids duplicate column names" do
      sql = "SELECT * FROM users WHERE email = 'test@example.com' AND email != ''"
      columns = extractor.extract_where_columns(sql)
      expect(columns.count("email")).to eq(1)
    end

    it "skips SQL keywords as columns" do
      sql = "SELECT * FROM users WHERE status = 'active' AND role NOT NULL"
      columns = extractor.extract_where_columns(sql)
      expect(columns).to include("status")
      expect(columns).not_to include("not", "null")
    end

    it "handles Rails timestamp queries" do
      sql = "SELECT * FROM users WHERE created_at >= '2024-01-01' AND updated_at < NOW()"
      columns = extractor.extract_where_columns(sql)
      expect(columns).to include("created_at", "updated_at")
    end

    it "handles quoted identifiers" do
      sql = 'SELECT * FROM "users" WHERE "email" = \'test@example.com\''
      # Pattern matching with quoted identifiers - conservative approach doesn't extract from quotes
      columns = extractor.extract_where_columns(sql)
      # Conservative: skips quoted identifiers, so result expected to be empty
      expect(columns).to eq([])
    end
  end

  describe "#extract_order_by_columns" do
    it "extracts single ORDER BY column" do
      sql = "SELECT * FROM users ORDER BY created_at"
      expect(extractor.extract_order_by_columns(sql)).to eq(["created_at"])
    end

    it "extracts multiple ORDER BY columns" do
      sql = "SELECT * FROM users ORDER BY status ASC, created_at DESC"
      columns = extractor.extract_order_by_columns(sql)
      expect(columns).to include("status", "created_at")
    end

    it "removes ASC/DESC modifiers" do
      sql = "SELECT * FROM events ORDER BY priority DESC, created_at ASC"
      columns = extractor.extract_order_by_columns(sql)
      expect(columns).to eq(["priority", "created_at"])
    end

    it "handles trailing LIMIT clause" do
      sql = "SELECT * FROM users ORDER BY created_at DESC LIMIT 10"
      expect(extractor.extract_order_by_columns(sql)).to eq(["created_at"])
    end

    it "returns empty array for no ORDER BY clause" do
      sql = "SELECT * FROM users WHERE status = 'active'"
      expect(extractor.extract_order_by_columns(sql)).to eq([])
    end

    it "returns empty array for nil input" do
      expect(extractor.extract_order_by_columns(nil)).to eq([])
    end

    it "returns empty array for empty string" do
      expect(extractor.extract_order_by_columns("")).to eq([])
    end

    it "is case-insensitive" do
      sql = "select * from users order by created_at asc"
      expect(extractor.extract_order_by_columns(sql)).to eq(["created_at"])
    end

    it "avoids duplicate column names" do
      sql = "SELECT * FROM users ORDER BY status DESC, status ASC"
      columns = extractor.extract_order_by_columns(sql)
      expect(columns.count("status")).to eq(1)
    end

    it "skips SQL keywords" do
      sql = "SELECT * FROM users ORDER BY status DESC, created_at ASC"
      columns = extractor.extract_order_by_columns(sql)
      expect(columns).not_to include("desc", "asc")
    end
  end

  describe "#extract_all_columns" do
    it "returns both WHERE and ORDER BY columns" do
      sql = "SELECT * FROM users WHERE status = 'active' ORDER BY created_at DESC"
      result = extractor.extract_all_columns(sql)

      expect(result[:where_columns]).to eq(["status"])
      expect(result[:order_by_columns]).to eq(["created_at"])
    end

    it "returns correct structure with empty arrays" do
      sql = "SELECT * FROM users"
      result = extractor.extract_all_columns(sql)

      expect(result).to have_key(:where_columns)
      expect(result).to have_key(:order_by_columns)
      expect(result[:where_columns]).to eq([])
      expect(result[:order_by_columns]).to eq([])
    end

    it "handles complex queries" do
      sql = "SELECT id, email FROM users WHERE status = 'active' AND created_at > '2024-01-01' ORDER BY created_at DESC, email ASC"
      result = extractor.extract_all_columns(sql)

      expect(result[:where_columns]).to include("status", "created_at")
      expect(result[:order_by_columns]).to eq(["created_at", "email"])
    end
  end

  describe "#extract_table_name" do
    it "extracts table name from simple SELECT" do
      sql = "SELECT * FROM users"
      expect(extractor.extract_table_name(sql)).to eq("users")
    end

    it "extracts table name from SELECT with WHERE" do
      sql = "SELECT id, email FROM users WHERE status = 'active'"
      expect(extractor.extract_table_name(sql)).to eq("users")
    end

    it "handles schema-qualified table names" do
      sql = "SELECT * FROM public.users WHERE id = 1"
      expect(extractor.extract_table_name(sql)).to eq("users")
    end

    it "extracts first table from JOIN" do
      sql = "SELECT * FROM users JOIN orders ON users.id = orders.user_id"
      expect(extractor.extract_table_name(sql)).to eq("users")
    end

    it "is case-insensitive" do
      sql = "select * from users"
      expect(extractor.extract_table_name(sql)).to eq("users")
    end

    it "returns downcase table name" do
      sql = "SELECT * FROM UserAccounts"
      expect(extractor.extract_table_name(sql)).to eq("useraccounts")
    end

    it "returns nil for nil input" do
      expect(extractor.extract_table_name(nil)).to be_nil
    end

    it "returns nil for empty string" do
      expect(extractor.extract_table_name("")).to be_nil
    end

    it "handles multiple spaces" do
      sql = "SELECT  *  FROM   users   WHERE id = 1"
      expect(extractor.extract_table_name(sql)).to eq("users")
    end
  end

  describe "Complex scenarios" do
    it "extracts index candidates from typical Rails query" do
      sql = "SELECT * FROM users WHERE status = 'active' AND email = 'test@example.com' ORDER BY created_at DESC"
      
      where_cols = extractor.extract_where_columns(sql)
      order_cols = extractor.extract_order_by_columns(sql)
      table = extractor.extract_table_name(sql)

      expect(where_cols).to include("status", "email")
      expect(order_cols).to eq(["created_at"])
      expect(table).to eq("users")
    end

    it "handles Rails timestamp queries" do
      sql = "SELECT * FROM posts WHERE user_id = 123 AND published = true AND created_at > '2024-01-01' ORDER BY created_at DESC LIMIT 20"
      
      where_cols = extractor.extract_where_columns(sql)
      order_cols = extractor.extract_order_by_columns(sql)

      expect(where_cols).to include("user_id", "published", "created_at")
      expect(order_cols).to eq(["created_at"])
    end

    it "extracts from real Devise/Auth query" do
      sql = "SELECT * FROM users WHERE email = ? AND encrypted_password IS NOT NULL"
      
      where_cols = extractor.extract_where_columns(sql)
      # Conservative: only extracts simple operators (=, <, >, etc), not IS NOT NULL
      expect(where_cols).to eq(["email"])
    end

    it "extracts from ActiveRecord scoped query" do
      sql = "SELECT * FROM comments WHERE post_id = 42 AND deleted_at IS NULL ORDER BY id DESC"
      
      where_cols = extractor.extract_where_columns(sql)
      order_cols = extractor.extract_order_by_columns(sql)

      # Conservative: only extracts simple operators (=, <, >, etc), not IS NULL
      expect(where_cols).to eq(["post_id"])
      expect(order_cols).to eq(["id"])
    end

    it "handles multiple ORDER BY with same column" do
      # Edge case: same column mentioned twice shouldn't create duplicates
      sql = "SELECT * FROM events ORDER BY type ASC, type DESC"
      order_cols = extractor.extract_order_by_columns(sql)
      
      expect(order_cols.count("type")).to eq(1)
    end

    it "handles WHERE with function calls gracefully" do
      sql = "SELECT * FROM events WHERE DATE(created_at) = '2024-01-01'"
      where_cols = extractor.extract_where_columns(sql)
      
      # Conservative: doesn't extract columns from function calls
      expect(where_cols).to eq([])
    end
  end
end
