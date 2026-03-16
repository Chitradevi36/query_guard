# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Analysis do
  describe "RiskLevel" do
    describe "constants" do
      it "defines risk levels" do
        expect(QueryGuard::Analysis::RiskLevel::LEVELS).to include(:low, :medium, :high, :critical)
      end

      it "defines severity levels" do
        expect(QueryGuard::Analysis::RiskLevel::SEVERITY_MAP).to include(:low, :medium, :high, :critical)
      end
    end

    describe ".valid?" do
      it "validates known risk levels" do
        expect(QueryGuard::Analysis::RiskLevel.valid?(:low)).to be true
        expect(QueryGuard::Analysis::RiskLevel.valid?(:medium)).to be true
        expect(QueryGuard::Analysis::RiskLevel.valid?(:high)).to be true
        expect(QueryGuard::Analysis::RiskLevel.valid?(:critical)).to be true
      end

      it "rejects unknown risk levels" do
        expect(QueryGuard::Analysis::RiskLevel.valid?(:unknown)).to be false
      end
    end

    describe ".to_severity" do
      it "maps risk levels to severity" do
        expect(QueryGuard::Analysis::RiskLevel.to_severity(:low)).to eq(:info)
        expect(QueryGuard::Analysis::RiskLevel.to_severity(:medium)).to eq(:warn)
        expect(QueryGuard::Analysis::RiskLevel.to_severity(:high)).to eq(:error)
        expect(QueryGuard::Analysis::RiskLevel.to_severity(:critical)).to eq(:error)
      end
    end
  end

  describe "RiskDetector" do
    let(:query) do
      QueryGuard::Core::Query.new(
        sql: "SELECT * FROM users",
        name: "User.all",
        duration_ms: 10
      )
    end
    let(:config) { QueryGuard::Config.new }

    describe "base class behavior" do
      it "raises NotImplementedError when detect is not implemented" do
        detector = QueryGuard::Analysis::RiskDetector.new
        expect { detector.detect(query, config) }.to raise_error(NotImplementedError)
      end
    end

    context "SelectStarRiskDetector" do
      let(:detector) { QueryGuard::Analysis::SelectStarRiskDetector.new }

      it "detects SELECT * pattern" do
        query = QueryGuard::Core::Query.new(
          sql: "SELECT * FROM users",
          name: "User.all",
          duration_ms: 10
        )

        risks = detector.detect(query, config)
        expect(risks).not_to be_empty
        expect(risks.first[:pattern]).to eq(:select_star)
      end

      it "does not detect SELECT with specific columns" do
        query = QueryGuard::Core::Query.new(
          sql: "SELECT id, name, email FROM users",
          name: "User.all",
          duration_ms: 10
        )

        risks = detector.detect(query, config)
        expect(risks).to be_empty
      end

      it "detects SELECT * even with WHERE clause" do
        query = QueryGuard::Core::Query.new(
          sql: "SELECT * FROM users WHERE id = 1",
          name: "User.find",
          duration_ms: 10
        )

        risks = detector.detect(query, config)
        expect(risks).not_to be_empty
      end
    end

    context "ComplexJoinRiskDetector" do
      let(:detector) { QueryGuard::Analysis::ComplexJoinRiskDetector.new }

      it "detects 5+ table joins" do
        sql = <<~SQL
          SELECT * FROM a
          JOIN b ON a.id = b.a_id
          JOIN c ON b.id = c.b_id
          JOIN d ON c.id = d.c_id
          JOIN e ON d.id = e.d_id
        SQL

        query = QueryGuard::Core::Query.new(
          sql: sql,
          name: "ComplexReport",
          duration_ms: 100
        )

        risks = detector.detect(query, config)
        expect(risks).not_to be_empty
        expect(risks.first[:pattern]).to eq(:many_joins)
      end

      it "does not flag fewer than 5 joins" do
        sql = <<~SQL
          SELECT * FROM a
          JOIN b ON a.id = b.a_id
          JOIN c ON b.id = c.b_id
          JOIN d ON c.id = d.c_id
        SQL

        query = QueryGuard::Core::Query.new(
          sql: sql,
          name: "Report",
          duration_ms: 50
        )

        risks = detector.detect(query, config)
        expect(risks).to be_empty
      end
    end

    context "SubqueryRiskDetector" do
      let(:detector) { QueryGuard::Analysis::SubqueryRiskDetector.new }

      it "detects subqueries" do
        query = QueryGuard::Core::Query.new(
          sql: "SELECT id FROM users WHERE id IN (SELECT user_id FROM orders)",
          name: "User.with_orders",
          duration_ms: 50
        )

        risks = detector.detect(query, config)
        expect(risks).not_to be_empty
        expect(risks.first[:pattern]).to eq(:nested_subqueries)
      end

      it "detects nested subqueries" do
        query = QueryGuard::Core::Query.new(
          sql: "SELECT id FROM users WHERE id IN (SELECT user_id FROM orders WHERE order_id IN (SELECT id FROM transactions))",
          name: "ComplexQuery",
          duration_ms: 100
        )

        risks = detector.detect(query, config)
        expect(risks).not_to be_empty
      end

      it "does not flag queries without subqueries" do
        query = QueryGuard::Core::Query.new(
          sql: "SELECT u.id FROM users u JOIN orders o ON u.id = o.user_id",
          name: "User.with_orders",
          duration_ms: 50
        )

        risks = detector.detect(query, config)
        expect(risks).to be_empty
      end
    end

    context "UnionRiskDetector" do
      let(:detector) { QueryGuard::Analysis::UnionRiskDetector.new }

      it "detects UNION queries" do
        query = QueryGuard::Core::Query.new(
          sql: "SELECT id FROM users UNION SELECT id FROM admins",
          name: "AllUsers",
          duration_ms: 50
        )

        risks = detector.detect(query, config)
        expect(risks).not_to be_empty
        expect(risks.first[:pattern]).to eq(:union_query)
      end

      it "suggests UNION ALL when appropriate" do
        query = QueryGuard::Core::Query.new(
          sql: "SELECT id FROM users UNION SELECT id FROM admins",
          name: "AllUsers",
          duration_ms: 50
        )

        risks = detector.detect(query, config)
        expect(risks.first[:message]).to include("UNION ALL")
      end
    end
  end

  describe "QueryRiskClassifier" do
    let(:classifier) { QueryGuard::Analysis::QueryRiskClassifier.new(config) }
    let(:config) { QueryGuard::Config.new }

    describe "#analyze_query" do
      it "runs all detectors on a query" do
        query = QueryGuard::Core::Query.new(
          sql: "SELECT * FROM users",
          name: "User.all",
          duration_ms: 10
        )

        risks = classifier.analyze_query(query)
        expect(risks).not_to be_empty
      end

      it "returns array of risk hashes" do
        query = QueryGuard::Core::Query.new(
          sql: "SELECT * FROM users",
          name: "User.all",
          duration_ms: 10
        )

        risks = classifier.analyze_query(query)
        expect(risks).to be_an(Array)
        expect(risks.first).to be_a(Hash)
        expect(risks.first).to include(:pattern, :risk_level, :message, :metadata)
      end

      it "combines risks from multiple detectors" do
        query = QueryGuard::Core::Query.new(
          sql: "SELECT * FROM users WHERE name LIKE '%test%'",
          name: "User.search",
          duration_ms: 100
        )

        risks = classifier.analyze_query(query)
        patterns = risks.map { |r| r[:pattern] }

        # Should have select_star and like_without_index
        expect(patterns).to include(:select_star)
        expect(patterns).to include(:like_without_index)
      end
    end

    describe "#analyze_context_risks" do
      it "detects repeated queries" do
        context = QueryGuard::Core::Context.new
        sql = "SELECT * FROM users WHERE id = ?"

        # Add same query 4 times
        4.times do |i|
          context.add_query(
            sql: sql.sub("?", i.to_s),
            name: "User.find",
            duration_ms: 10
          )
        end

        risks = classifier.analyze_context_risks(context)
        repeated = risks.find { |r| r[:pattern] == :repeated_query }

        expect(repeated).not_to be_nil
        expect(repeated[:message]).to include("4 times")
      end

      it "detects N+1 patterns" do
        context = QueryGuard::Core::Context.new

        # Add 10 SELECT queries from only 2 tables
        10.times do |i|
          sql = i.even? ? "SELECT * FROM users WHERE id = #{i}" : "SELECT * FROM orders WHERE user_id = #{i}"
          context.add_query(sql: sql, name: "query", duration_ms: 5)
        end

        risks = classifier.analyze_context_risks(context)
        n_plus_one = risks.find { |r| r[:pattern] == :potential_n_plus_one }

        expect(n_plus_one).not_to be_nil
      end

      it "returns empty array when no context-level risks" do
        context = QueryGuard::Core::Context.new
        context.add_query(sql: "SELECT id FROM users LIMIT 1", name: "User.first", duration_ms: 5)

        risks = classifier.analyze_context_risks(context)
        expect(risks).to be_empty
      end
    end

    describe "#normalize_sql" do
      it "normalizes parameter placeholders" do
        sql = "SELECT id FROM users WHERE id = 123 AND name = 'john'"
        normalized = classifier.send(:normalize_sql, sql)

        # Should replace numbers and strings with ? for pattern matching
        expect(normalized).not_to include("123")
      end

      it "normalizes whitespace" do
        sql = "SELECT  *  FROM  users"
        normalized = classifier.send(:normalize_sql, sql)

        expect(normalized).not_to match(/\s{2,}/)
      end
    end

    describe "#extract_table_name" do
      it "extracts table name from FROM clause" do
        sql = "SELECT * FROM users WHERE id = 1"
        table = classifier.send(:extract_table_name, sql)

        expect(table).to eq("users")
      end

      it "extracts from JOIN clauses" do
        sql = "SELECT * FROM users JOIN orders ON users.id = orders.user_id"
        tables = sql.scan(/(?:FROM|JOIN)\s+(\w+)/i).flatten

        expect(tables).to include("users", "orders")
      end

      it "handles table aliases" do
        sql = "SELECT * FROM users u WHERE u.id = 1"
        table = classifier.send(:extract_table_name, sql)

        expect(table).to eq("users")
      end
    end
  end
end
