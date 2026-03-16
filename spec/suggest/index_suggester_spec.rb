# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Suggest::IndexSuggester do
  let(:suggester) { described_class.new }

  describe "#suggest_for_sequential_scan" do
    it "suggests index for simple WHERE clause" do
      sql = "SELECT * FROM users WHERE email = 'test@example.com'"
      suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "users")

      expect(suggestion).not_to be_nil
      expect(suggestion[:suggested_index_sql]).to include("CREATE INDEX")
      expect(suggestion[:suggested_index_sql]).to include("users")
      expect(suggestion[:suggested_index_sql]).to include("email")
      expect(suggestion[:columns]).to eq(["email"])
    end

    it "returns nil for query without WHERE clause" do
      sql = "SELECT * FROM users"
      suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "users")

      expect(suggestion).to be_nil
    end

    it "returns nil for nil query" do
      suggestion = suggester.suggest_for_sequential_scan(nil, table_name: "users")
      expect(suggestion).to be_nil
    end

    it "returns nil for nil table name" do
      sql = "SELECT * FROM users WHERE id = 1"
      suggestion = suggester.suggest_for_sequential_scan(sql, table_name: nil)

      expect(suggestion).to be_nil
    end

    it "uses first column from multiple WHERE conditions" do
      sql = "SELECT * FROM users WHERE status = 'active' AND email = 'test@example.com'"
      suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "users")

      # Should use first column (status)
      expect(suggestion[:columns]).to eq(["status"])
      expect(suggestion[:suggested_index_sql]).to include("status")
    end

    it "includes explanation in suggestion" do
      sql = "SELECT * FROM users WHERE email = 'test@example.com'"
      suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "users")

      expect(suggestion[:explanation]).to include("email")
      expect(suggestion[:explanation]).to include("column filter")
    end

    it "sets high confidence for sequential scan" do
      sql = "SELECT * FROM users WHERE email = 'test@example.com'"
      suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "users")

      expect(suggestion[:confidence]).to eq(:high)
    end

    it "generates valid PostgreSQL index name" do
      sql = "SELECT * FROM users WHERE email = 'test@example.com'"
      suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "users")

      expect(suggestion[:index_name]).to match(/^idx_/)
      expect(suggestion[:index_name]).to match(/users/)
      expect(suggestion[:index_name]).to match(/email/)
    end

    it "handles table names with special characters" do
      sql = "SELECT * FROM user_accounts WHERE email = 'test@example.com'"
      suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "user_accounts")

      expect(suggestion[:suggested_index_sql]).to include("user_accounts")
      expect(suggestion[:index_name]).to include("user_accounts")
    end
  end

  describe "#suggest_for_expensive_sort" do
    it "suggests index for ORDER BY clause" do
      sql = "SELECT * FROM events ORDER BY created_at DESC"
      suggestion = suggester.suggest_for_expensive_sort(sql, table_name: "events")

      expect(suggestion).not_to be_nil
      expect(suggestion[:suggested_index_sql]).to include("CREATE INDEX")
      expect(suggestion[:suggested_index_sql]).to include("created_at")
      expect(suggestion[:columns]).to eq(["created_at"])
    end

    it "suggests composite index for multiple ORDER BY columns" do
      sql = "SELECT * FROM events ORDER BY status ASC, created_at DESC"
      suggestion = suggester.suggest_for_expensive_sort(sql, table_name: "events")

      expect(suggestion).not_to be_nil
      expect(suggestion[:columns]).to eq(["status", "created_at"])
      expect(suggestion[:suggested_index_sql]).to include("status")
      expect(suggestion[:suggested_index_sql]).to include("created_at")
    end

    it "returns nil for query without ORDER BY" do
      sql = "SELECT * FROM events"
      suggestion = suggester.suggest_for_expensive_sort(sql, table_name: "events")

      expect(suggestion).to be_nil
    end

    it "returns nil for nil query" do
      suggestion = suggester.suggest_for_expensive_sort(nil, table_name: "events")
      expect(suggestion).to be_nil
    end

    it "returns nil for nil table name" do
      sql = "SELECT * FROM events ORDER BY created_at"
      suggestion = suggester.suggest_for_expensive_sort(sql, table_name: nil)

      expect(suggestion).to be_nil
    end

    it "includes sort reason in explanation" do
      sql = "SELECT * FROM events ORDER BY created_at DESC"
      suggestion = suggester.suggest_for_expensive_sort(sql, table_name: "events")

      expect(suggestion[:explanation]).to include("ORDER BY")
    end

    it "sets medium confidence for sort index" do
      sql = "SELECT * FROM events ORDER BY created_at DESC"
      suggestion = suggester.suggest_for_expensive_sort(sql, table_name: "events")

      expect(suggestion[:confidence]).to eq(:medium)
    end

    it "limits composite indexes to reasonable size" do
      # Suggest up to 4 columns, not more
      sql = "SELECT * FROM events ORDER BY a ASC, b DESC, c ASC, d DESC, e ASC"
      suggestion = suggester.suggest_for_expensive_sort(sql, table_name: "events")

      # Should return nil or limited subset, not all 5 columns
      if suggestion
        expect(suggestion[:columns].length).to be <= 4
      end
    end
  end

  describe "#suggest_for_complex_filter" do
    it "suggests composite index for multiple WHERE conditions" do
      sql = "SELECT * FROM users WHERE status = 'active' AND role = 'admin'"
      suggestion = suggester.suggest_for_complex_filter(sql, table_name: "users")

      expect(suggestion).not_to be_nil
      expect(suggestion[:columns]).to include("status", "role")
      expect(suggestion[:suggested_index_sql]).to include("status")
      expect(suggestion[:suggested_index_sql]).to include("role")
    end

    it "returns nil for single WHERE condition" do
      sql = "SELECT * FROM users WHERE email = 'test@example.com'"
      suggestion = suggester.suggest_for_complex_filter(sql, table_name: "users")

      expect(suggestion).to be_nil
    end

    it "returns nil for too many columns" do
      sql = "SELECT * FROM users WHERE a = 1 AND b = 2 AND c = 3 AND d = 4 AND e = 5"
      suggestion = suggester.suggest_for_complex_filter(sql, table_name: "users")

      # Should return nil for >3 columns (conservative)
      expect(suggestion).to be_nil
    end

    it "includes composite filter reason" do
      sql = "SELECT * FROM users WHERE status = 'active' AND role = 'admin'"
      suggestion = suggester.suggest_for_complex_filter(sql, table_name: "users")

      expect(suggestion[:explanation]).to include("Composite")
    end

    it "sets medium confidence for composite index" do
      sql = "SELECT * FROM users WHERE status = 'active' AND role = 'admin'"
      suggestion = suggester.suggest_for_complex_filter(sql, table_name: "users")

      expect(suggestion[:confidence]).to eq(:medium)
    end
  end

  describe "#suggest_for_join" do
    it "suggests index for join column" do
      suggestion = suggester.suggest_for_join("user_id", table_name: "orders")

      expect(suggestion).not_to be_nil
      expect(suggestion[:suggested_index_sql]).to include("user_id")
      expect(suggestion[:columns]).to eq(["user_id"])
    end

    it "returns nil for nil column name" do
      suggestion = suggester.suggest_for_join(nil, table_name: "orders")
      expect(suggestion).to be_nil
    end

    it "returns nil for nil table name" do
      suggestion = suggester.suggest_for_join("user_id", table_name: nil)
      expect(suggestion).to be_nil
    end

    it "sets high confidence for join index" do
      suggestion = suggester.suggest_for_join("user_id", table_name: "orders")
      expect(suggestion[:confidence]).to eq(:high)
    end

    it "includes join reason" do
      suggestion = suggester.suggest_for_join("user_id", table_name: "orders")
      expect(suggestion[:explanation]).to include("JOIN")
    end
  end

  describe "#build_recommendation_text" do
    it "includes SQL statement in recommendation" do
      sql = "SELECT * FROM users WHERE email = 'test@example.com'"
      suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "users")
      
      text = suggester.build_recommendation_text(suggestion)
      expect(text).to include(suggestion[:suggested_index_sql])
    end

    it "includes confidence level" do
      sql = "SELECT * FROM users WHERE email = 'test@example.com'"
      suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "users")
      
      text = suggester.build_recommendation_text(suggestion)
      expect(text).to include("confidence")
      expect(text).to include("high")
    end

    it "includes important disclaimers" do
      sql = "SELECT * FROM users WHERE email = 'test@example.com'"
      suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "users")
      
      text = suggester.build_recommendation_text(suggestion)
      expect(text).to include("IMPORTANT: This is a recommendation")
      expect(text).to include("EXPLAIN ANALYZE")
      expect(text).to include("selectivity")
      expect(text).to include("development first")
    end

    it "handles nil suggestion gracefully" do
      text = suggester.build_recommendation_text(nil)
      expect(text).to be_nil
    end
  end

  describe "Index naming" do
    it "sanitizes table names with special characters" do
      sql = "SELECT * FROM user-accounts WHERE id = 1"
      suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "user-accounts")

      # Should have converted dash to underscore
      expect(suggestion[:index_name]).to match(/^idx_user_accounts/)
    end

    it "handles column names with special characters" do
      sql = "SELECT * FROM users WHERE email = 'test@example.com'"
      suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "users")

      # Should create valid identifier
      expect(suggestion[:index_name]).to match(/^idx_/)
      # No special characters in the index name
      expect(suggestion[:index_name]).not_to include("-")
      expect(suggestion[:index_name]).not_to include(" ")
    end

    it "respects PostgreSQL identifier length limit" do
      # PostgreSQL identifiers limited to 63 characters
      suggestion = suggester.suggest_for_sequential_scan(
        "SELECT * FROM very_long_table_name WHERE col1 = 1 AND col2 = 2 AND col3 = 3",
        table_name: "very_long_table_name"
      )

      expect(suggestion[:index_name].length).to be <= 63
    end
  end

  describe "Real-world query patterns" do
    it "handles typical Rails User query" do
      sql = "SELECT * FROM users WHERE email = 'test@example.com' AND encrypted_password IS NOT NULL"
      suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "users")

      expect(suggestion).not_to be_nil
      expect(suggestion[:columns]).to eq(["email"])
    end

    it "handles typical Rails Post query with timestamps" do
      sql = "SELECT * FROM posts WHERE user_id = 123 AND published_at > '2024-01-01' ORDER BY published_at DESC LIMIT 10"
      
      where_suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "posts")
      expect(where_suggestion[:columns]).to eq(["user_id"])

      order_suggestion = suggester.suggest_for_expensive_sort(sql, table_name: "posts")
      expect(order_suggestion[:columns]).to eq(["published_at"])
    end

    it "handles soft delete query (Rails paranoia)" do
      sql = "SELECT * FROM comments WHERE post_id = 42 AND deleted_at IS NULL ORDER BY created_at DESC"
      
      suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "comments")
      expect(suggestion[:columns]).to eq(["post_id"])
    end

    it "handles composite query with reasonable suggestions" do
      sql = "SELECT * FROM orders WHERE user_id = 123 AND status = 'pending' ORDER BY created_at DESC"
      
      where_suggestion = suggester.suggest_for_sequential_scan(sql, table_name: "orders")
      expect(where_suggestion).not_to be_nil
      
      complex_suggestion = suggester.suggest_for_complex_filter(sql, table_name: "orders")
      expect(complex_suggestion).not_to be_nil # Multiple WHERE conditions
      
      order_suggestion = suggester.suggest_for_expensive_sort(sql, table_name: "orders")
      expect(order_suggestion).not_to be_nil
    end
  end
end
