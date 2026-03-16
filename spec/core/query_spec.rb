# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Core::Query do
  describe "initialization" do
    it "creates a query with all attributes" do
      now = Time.now
      query = described_class.new(
        sql: "SELECT * FROM users",
        duration_ms: 123.45,
        name: "User Load",
        started_at: now,
        finished_at: now + 0.123
      )

      expect(query.sql).to eq("SELECT * FROM users")
      expect(query.duration_ms).to eq(123.45)
      expect(query.name).to eq("User Load")
      expect(query.started_at).to eq(now)
    end

    it "freezes sql string for immutability" do
      query = described_class.new(sql: "SELECT 1", duration_ms: 10)
      expect(query.sql).to be_frozen
    end

    it "handles nil name gracefully" do
      query = described_class.new(sql: "SELECT 1", duration_ms: 10, name: nil)
      expect(query.name).to be_nil
    end
  end

  describe "#to_h" do
    it "serializes to hash" do
      now = Time.now
      query = described_class.new(
        sql: "SELECT * FROM posts",
        duration_ms: 50.5,
        name: "Post Load",
        started_at: now
      )

      hash = query.to_h
      expect(hash[:sql]).to eq("SELECT * FROM posts")
      expect(hash[:duration_ms]).to eq(50.5)
      expect(hash[:name]).to eq("Post Load")
      expect(hash[:started_at]).to eq(now.iso8601)
    end
  end

  describe "#inspect" do
    it "provides useful inspection string" do
      query = described_class.new(sql: "SELECT * FROM users WHERE id = ?", duration_ms: 125.5)
      expect(query.inspect).to include("Query")
      expect(query.inspect).to include("duration_ms=125.5")
    end
  end
end
