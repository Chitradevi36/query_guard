# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Analysis::RiskDetector do
  describe "SelectStarRiskDetector" do
    subject(:detector) { QueryGuard::Analysis::SelectStarRiskDetector.new }

    it "detects SELECT * in simple queries" do
      query = build_query("SELECT * FROM users")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks).to have_risk(:select_star)
    end

    it "detects SELECT * with WHERE clause" do
      query = build_query("SELECT * FROM users WHERE status = 'active'")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks).to have_risk(:select_star)
    end

    it "detects SELECT * with JOIN" do
      query = build_query("SELECT * FROM users u JOIN orders o ON u.id = o.user_id")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks).to have_risk(:select_star)
    end

    it "ignores specific column selection" do
      query = build_query("SELECT id, name, email FROM users")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks).not_to have_risk(:select_star)
    end

    it "ignores SELECT count(*)" do
      query = build_query("SELECT COUNT(*) FROM users")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks).not_to have_risk(:select_star)
    end

    it "returns medium risk level" do
      query = build_query("SELECT * FROM users")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks.first[:risk_level]).to eq(:medium)
    end
  end

  describe "MissingIndexRiskDetector" do
    subject(:detector) { QueryGuard::Analysis::MissingIndexRiskDetector.new }

    it "detects LIKE without leading%" do
      query = build_query("SELECT * FROM users WHERE name LIKE 'john%'")
      risks = detector.detect(query, QueryGuard::Config.new)
      # This should not be detected as problematic (prefix search can use index)
      expect(risks.select { |r| r[:pattern] == :like_without_index }).to be_empty
    end

    it "detects LIKE with % prefix" do
      query = build_query("SELECT * FROM users WHERE name LIKE '%john%'")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks.map { |r| r[:pattern] }).to include(:like_without_index)
    end

    it "detects functions in JOIN conditions" do
      query = build_query("SELECT * FROM orders o JOIN users u ON LOWER(o.email) = LOWER(u.email)")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks.map { |r| r[:pattern] }).to include(:function_in_join)
    end

    it "ignores plain column JOINs" do
      query = build_query("SELECT * FROM orders o JOIN users u ON o.user_id = u.id")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks.select { |r| r[:pattern] == :function_in_join }).to be_empty
    end

    it "returns high risk level for LIKE without index" do
      query = build_query("SELECT * FROM users WHERE name LIKE '%smith%'")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks.first[:risk_level]).to eq(:high)
    end
  end

  describe "ComplexJoinRiskDetector" do
    subject(:detector) { QueryGuard::Analysis::ComplexJoinRiskDetector.new }

    it "ignores queries with fewer than 5 joins" do
      query = build_query(<<~SQL
        SELECT * FROM a
        JOIN b ON a.id = b.a_id
        JOIN c ON b.id = c.b_id
      SQL
      )
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks).not_to have_risk(:many_joins)
    end

    it "detects queries with 5+ joins" do
      query = build_query(<<~SQL
        SELECT * FROM a
        JOIN b ON a.id = b.a_id
        JOIN c ON b.id = c.b_id
        JOIN d ON c.id = d.c_id
        JOIN e ON d.id = e.d_id
      SQL
      )
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks).to have_risk(:many_joins)
    end

    it "counts both JOIN and LEFT JOIN" do
      query = build_query(<<~SQL
        SELECT * FROM a
        LEFT JOIN b ON a.id = b.a_id
        JOIN c ON b.id = c.b_id
        INNER JOIN d ON c.id = d.c_id
        OUTER JOIN e ON d.id = e.d_id
      SQL
      )
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks).to have_risk(:many_joins)
    end

    it "returns medium risk level" do
      query = build_query(<<~SQL
        SELECT * FROM a
        JOIN b ON a.id = b.a_id
        JOIN c ON b.id = c.b_id
        JOIN d ON c.id = d.c_id
        JOIN e ON d.id = e.d_id
      SQL
      )
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks.first[:risk_level]).to eq(:medium)
    end
  end

  describe "SubqueryRiskDetector" do
    subject(:detector) { QueryGuard::Analysis::SubqueryRiskDetector.new }

    it "detects single subquery" do
      query = build_query("SELECT id FROM users WHERE id IN (SELECT user_id FROM orders)")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks).to have_risk(:nested_subqueries)
    end

    it "detects EXISTS subquery" do
      query = build_query("SELECT id FROM users WHERE EXISTS (SELECT 1 FROM orders WHERE user_id = users.id)")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks).to have_risk(:nested_subqueries)
    end

    it "detects nested subqueries" do
      query = build_query("SELECT id FROM users WHERE id IN (SELECT user_id FROM orders WHERE order_id IN (SELECT id FROM transactions))")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks).to have_risk(:nested_subqueries)
    end

    it "ignores queries without subqueries" do
      query = build_query("SELECT u.id FROM users u JOIN orders o ON u.id = o.user_id")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks).not_to have_risk(:nested_subqueries)
    end

    it "returns appropriate risk level for depth" do
      query = build_query("SELECT id FROM users WHERE id IN (SELECT user_id FROM orders)")
      risks = detector.detect(query, QueryGuard::Config.new)
      # Single subquery is medium risk
      expect(risks.first[:risk_level]).to eq(:medium)
    end
  end

  describe "UnionRiskDetector" do
    subject(:detector) { QueryGuard::Analysis::UnionRiskDetector.new }

    it "detects UNION queries" do
      query = build_query("SELECT id FROM users UNION SELECT id FROM admins")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks).to have_risk(:union_query)
    end

    it "ignores UNION ALL queries" do
      query = build_query("SELECT id FROM users UNION ALL SELECT id FROM admins")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks).not_to have_risk(:union_query)
    end

    it "detects multiple UNIONs" do
      query = build_query("SELECT id FROM users UNION SELECT id FROM admins UNION SELECT id FROM mods")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks).to have_risk(:union_query)
    end

    it "returns low risk level" do
      query = build_query("SELECT id FROM users UNION SELECT id FROM admins")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks.first[:risk_level]).to eq(:low)
    end
  end

  describe "AggregationRiskDetector" do
    subject(:detector) { QueryGuard::Analysis::AggregationRiskDetector.new }

    it "detects DISTINCT" do
      query = build_query("SELECT DISTINCT category FROM products")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks).to have_risk(:distinct_usage)
    end

    it "detects GROUP BY" do
      query = build_query("SELECT category, COUNT(*) FROM products GROUP BY category")
      risks = detector.detect(query, QueryGuard::Config.new)
      # GROUP BY without ORDER BY is detected
      expect(risks.map { |r| r[:pattern] }).to include(:group_by_unordered)
    end

    it "ignores GROUP BY with ORDER BY" do
      query = build_query("SELECT category, COUNT(*) FROM products GROUP BY category ORDER BY COUNT(*) DESC")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks.select { |r| r[:pattern] == :group_by_unordered }).to be_empty
    end

    it "returns low risk level" do
      query = build_query("SELECT DISTINCT category FROM products")
      risks = detector.detect(query, QueryGuard::Config.new)
      expect(risks.first[:risk_level]).to eq(:low)
    end
  end

  # MARK: - Helpers

  def build_query(sql)
    QueryGuard::Core::Query.new(
      sql: sql,
      name: "test_query",
      duration_ms: 10
    )
  end
end

# RSpec matcher helper
RSpec::Matchers.define :have_risk do |expected_pattern|
  match do |risks|
    risks.any? { |risk| risk[:pattern] == expected_pattern }
  end

  failure_message do |risks|
    patterns = risks.map { |r| r[:pattern] }
    "expected to find risk pattern #{expected_pattern.inspect}, but found #{patterns.inspect}"
  end
end
