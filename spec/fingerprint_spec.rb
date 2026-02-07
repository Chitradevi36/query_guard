# frozen_string_literal: true

require "spec_helper"
require "query_guard/fingerprint"

RSpec.describe QueryGuard::Fingerprint do
  after do
    described_class.reset!
  end

  describe ".normalize" do
    it "normalizes whitespace" do
      sql = "SELECT  *  FROM   users"
      expect(described_class.normalize(sql)).to eq("select * from users")
    end

    it "replaces string literals with ?" do
      sql = "SELECT * FROM users WHERE name = 'John Doe'"
      expect(described_class.normalize(sql)).to eq("select * from users where name = ?")
    end

    it "replaces numeric literals with ?" do
      sql = "SELECT * FROM users WHERE id = 123 AND age > 21"
      expect(described_class.normalize(sql)).to eq("select * from users where id = ? and age > ?")
    end

    it "replaces IN lists with IN (?)" do
      sql = "SELECT * FROM users WHERE id IN (1, 2, 3, 4)"
      expect(described_class.normalize(sql)).to eq("select * from users where id in (?)")
    end

    it "handles complex queries" do
      sql = <<~SQL
        SELECT users.*, posts.title
        FROM users
        LEFT JOIN posts ON posts.user_id = users.id
        WHERE users.email = 'test@example.com'
        AND users.created_at > '2024-01-01'
        AND users.status IN ('active', 'pending')
        ORDER BY users.id
        LIMIT 10
      SQL
      
      normalized = described_class.normalize(sql)
      expect(normalized).not_to include("test@example.com")
      expect(normalized).not_to include("2024-01-01")
      expect(normalized).not_to include("active")
      expect(normalized).to include("?")
    end
  end

  describe ".generate" do
    it "generates consistent fingerprints for identical queries" do
      sql1 = "SELECT * FROM users WHERE id = 1"
      sql2 = "SELECT * FROM users WHERE id = 1"
      
      expect(described_class.generate(sql1)).to eq(described_class.generate(sql2))
    end

    it "generates same fingerprint for queries with different literals" do
      sql1 = "SELECT * FROM users WHERE id = 1"
      sql2 = "SELECT * FROM users WHERE id = 999"
      
      expect(described_class.generate(sql1)).to eq(described_class.generate(sql2))
    end

    it "generates different fingerprints for structurally different queries" do
      sql1 = "SELECT * FROM users WHERE id = 1"
      sql2 = "SELECT * FROM posts WHERE id = 1"
      
      expect(described_class.generate(sql1)).not_to eq(described_class.generate(sql2))
    end

    it "returns a SHA1 hash" do
      sql = "SELECT * FROM users"
      fingerprint = described_class.generate(sql)
      
      expect(fingerprint).to match(/^[a-f0-9]{40}$/)
    end
  end

  describe ".record" do
    it "records query execution and returns fingerprint" do
      sql = "SELECT * FROM users WHERE id = 1"
      fp = described_class.record(sql, 10.5)
      
      expect(fp).to be_a(String)
      expect(fp.length).to eq(40)
    end

    it "increments count for repeated queries" do
      sql = "SELECT * FROM users WHERE id = ?"
      
      fp1 = described_class.record("SELECT * FROM users WHERE id = 1", 10)
      fp2 = described_class.record("SELECT * FROM users WHERE id = 2", 15)
      
      expect(fp1).to eq(fp2)
      expect(described_class.stats_for(fp1)[:count]).to eq(2)
    end

    it "tracks total duration" do
      sql = "SELECT * FROM users WHERE id = ?"
      
      fp = described_class.record("SELECT * FROM users WHERE id = 1", 10)
      described_class.record("SELECT * FROM users WHERE id = 2", 15)
      
      expect(described_class.stats_for(fp)[:total_duration_ms]).to eq(25)
    end

    it "tracks min and max duration" do
      sql = "SELECT * FROM users WHERE id = ?"
      
      fp = described_class.record("SELECT * FROM users WHERE id = 1", 20)
      described_class.record("SELECT * FROM users WHERE id = 2", 5)
      described_class.record("SELECT * FROM users WHERE id = 3", 50)
      
      stats = described_class.stats_for(fp)
      expect(stats[:min_duration_ms]).to eq(5)
      expect(stats[:max_duration_ms]).to eq(50)
    end

    it "tracks first and last seen timestamps" do
      sql = "SELECT * FROM users WHERE id = 1"
      fp = described_class.record(sql, 10)
      
      stats = described_class.stats_for(fp)
      expect(stats[:first_seen_at]).to be_a(Time)
      expect(stats[:last_seen_at]).to be_a(Time)
    end
  end

  describe ".stats_for" do
    it "returns stats for a specific fingerprint" do
      sql = "SELECT * FROM users WHERE id = 1"
      fp = described_class.record(sql, 10)
      
      stats = described_class.stats_for(fp)
      expect(stats[:count]).to eq(1)
      expect(stats[:total_duration_ms]).to eq(10)
    end

    it "returns default stats for unknown fingerprint" do
      stats = described_class.stats_for("unknown")
      expect(stats[:count]).to eq(0)
    end
  end

  describe ".top_by_count" do
    before do
      described_class.record("SELECT * FROM users WHERE id = 1", 10)
      described_class.record("SELECT * FROM users WHERE id = 2", 10)
      described_class.record("SELECT * FROM users WHERE id = 3", 10)
      
      described_class.record("SELECT * FROM posts WHERE id = 1", 20)
      described_class.record("SELECT * FROM posts WHERE id = 2", 20)
    end

    it "returns top queries by count" do
      top = described_class.top_by_count(2)
      
      expect(top.length).to eq(2)
      counts = top.values.map { |s| s[:count] }.sort.reverse
      expect(counts).to eq([3, 2])
    end

    it "limits results" do
      top = described_class.top_by_count(1)
      expect(top.length).to eq(1)
    end
  end

  describe ".top_by_duration" do
    before do
      described_class.record("SELECT * FROM users WHERE id = 1", 100)
      described_class.record("SELECT * FROM posts WHERE id = 1", 50)
    end

    it "returns top queries by total duration" do
      top = described_class.top_by_duration(2)
      
      expect(top.length).to eq(2)
      durations = top.values.map { |s| s[:total_duration_ms] }.sort.reverse
      expect(durations).to eq([100, 50])
    end
  end

  describe ".top_by_avg_duration" do
    before do
      # Query 1: 100ms total, 1 execution = 100ms avg
      described_class.record("SELECT * FROM users WHERE id = 1", 100)
      
      # Query 2: 100ms total, 2 executions = 50ms avg
      described_class.record("SELECT * FROM posts WHERE id = 1", 50)
      described_class.record("SELECT * FROM posts WHERE id = 2", 50)
    end

    it "returns top queries by average duration" do
      top = described_class.top_by_avg_duration(2)
      
      expect(top.length).to eq(2)
      # First should be the one with 100ms avg
      first_avg = top.values.first[:total_duration_ms] / top.values.first[:count]
      expect(first_avg).to eq(100)
    end
  end

  describe ".reset!" do
    it "clears all stats" do
      described_class.record("SELECT * FROM users WHERE id = 1", 10)
      expect(described_class.stats.length).to be > 0
      
      described_class.reset!
      expect(described_class.stats.length).to eq(0)
    end
  end
end
