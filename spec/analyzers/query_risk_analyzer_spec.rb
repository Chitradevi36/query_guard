# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryGuard::Analyzers::QueryRiskAnalyzer do
  let(:analyzer) { described_class.new }
  let(:config) { QueryGuard::Config.new }

  describe "#initialize" do
    it "has the name :query_risk" do
      expect(analyzer.name).to eq(:query_risk)
    end
  end

  describe "#analyze" do
    context "when analyze_query_risks is disabled" do
      before { config.analyze_query_risks = false }

      it "returns empty findings" do
        context = QueryGuard::Core::Context.new
        context.add_query(
          sql: "SELECT * FROM users",
          name: "User.find",
          duration_ms: 10
        )

        findings = analyzer.analyze(context, config)
        expect(findings).to be_empty
      end
    end

    context "when analyze_query_risks is enabled" do
      before { config.analyze_query_risks = true }

      context "with SELECT * query" do
        it "detects select star risk" do
          context = QueryGuard::Core::Context.new
          context.add_query(
            sql: "SELECT * FROM users WHERE id = 1",
            name: "User.find",
            duration_ms: 10
          )

          findings = analyzer.analyze(context, config)
          expect(findings).not_to be_empty

          select_star_finding = findings.find { |f| f.rule_name == :select_star }
          expect(select_star_finding).not_to be_nil
          expect(select_star_finding.title).to eq("SELECT * Usage")
          expect(select_star_finding.severity).to eq(:warn)
        end
      end

      context "with complex join query" do
        it "detects complex join risk" do
          context = QueryGuard::Core::Context.new
          sql = <<~SQL
            SELECT a.id, b.id, c.id, d.id, e.id, f.id
            FROM table_a a
            JOIN table_b b ON a.id = b.a_id
            JOIN table_c c ON b.id = c.b_id
            JOIN table_d d ON c.id = d.c_id
            JOIN table_e e ON d.id = e.d_id
            JOIN table_f f ON e.id = f.e_id
            WHERE a.status = 'active'
          SQL
          context.add_query(
            sql: sql,
            name: "ComplexReport.fetch",
            duration_ms: 150
          )

          findings = analyzer.analyze(context, config)
          join_finding = findings.find { |f| f.rule_name == :many_joins }
          expect(join_finding).not_to be_nil
          expect(join_finding.title).to eq("Complex Multi-Table Join")
        end
      end

      context "with subquery" do
        it "detects subquery risk" do
          context = QueryGuard::Core::Context.new
          context.add_query(
            sql: "SELECT id FROM users WHERE id IN (SELECT user_id FROM orders)",
            name: "User.with_orders",
            duration_ms: 50
          )

          findings = analyzer.analyze(context, config)
          subquery_finding = findings.find { |f| f.rule_name == :nested_subqueries }
          expect(subquery_finding).not_to be_nil
          expect(subquery_finding.severity).to eq(:warn)
        end
      end

      context "with UNION query" do
        it "detects union risk" do
          context = QueryGuard::Core::Context.new
          context.add_query(
            sql: "SELECT id FROM users UNION SELECT id FROM admins",
            name: "AllUsers.fetch",
            duration_ms: 50
          )

          findings = analyzer.analyze(context, config)
          union_finding = findings.find { |f| f.rule_name == :union_query }
          expect(union_finding).not_to be_nil
        end
      end

      context "with LIKE without index" do
        it "detects like without index risk" do
          context = QueryGuard::Core::Context.new
          context.add_query(
            sql: "SELECT id FROM users WHERE name LIKE '%john%'",
            name: "User.search",
            duration_ms: 200
          )

          findings = analyzer.analyze(context, config)
          like_finding = findings.find { |f| f.rule_name == :like_without_index }
          expect(like_finding).not_to be_nil
        end
      end

      context "with repeated queries" do
        it "detects repeated query in context" do
          context = QueryGuard::Core::Context.new
          sql = "SELECT * FROM users WHERE id = ?"

          # Add same query 3 times
          3.times do
            context.add_query(
              sql: sql.sub("?", rand(1..100).to_s),
              name: "User.find",
              duration_ms: 10
            )
          end

          findings = analyzer.analyze(context, config)
          repeated_finding = findings.find { |f| f.rule_name == :repeated_query }
          expect(repeated_finding).not_to be_nil
          expect(repeated_finding.title).to eq("Repeated Query in Request")
        end
      end

      context "with N+1 pattern" do
        it "detects n+1 query problem" do
          context = QueryGuard::Core::Context.new

          # Add 10 SELECT queries from only 2 tables
          10.times do |i|
            sql = i.even? ? "SELECT * FROM users WHERE id = #{i}" : "SELECT * FROM orders WHERE user_id = #{i}"
            context.add_query(sql: sql, name: "query", duration_ms: 5)
          end

          findings = analyzer.analyze(context, config)
          n_plus_one_finding = findings.find { |f| f.rule_name == :potential_n_plus_one }
          expect(n_plus_one_finding).not_to be_nil
          expect(n_plus_one_finding.title).to eq("Potential N+1 Query Problem")
        end
      end
    end

    context "finding attributes" do
      before { config.analyze_query_risks = true }

      it "includes sql in finding" do
        context = QueryGuard::Core::Context.new
        sql = "SELECT * FROM users"
        context.add_query(sql: sql, name: "User.all", duration_ms: 10)

        findings = analyzer.analyze(context, config)
        finding = findings.find { |f| f.rule_name == :select_star }

        expect(finding.sql).to eq(sql)
      end

      it "includes recommendations" do
        context = QueryGuard::Core::Context.new
        context.add_query(
          sql: "SELECT * FROM users",
          name: "User.all",
          duration_ms: 10
        )

        findings = analyzer.analyze(context, config)
        finding = findings.find { |f| f.rule_name == :select_star }

        expect(finding.recommendations).not_to be_empty
        expect(finding.recommendations.first).to include("Specify only required columns")
      end

      it "includes metadata" do
        context = QueryGuard::Core::Context.new
        context.add_query(
          sql: "SELECT * FROM users",
          name: "User.all",
          duration_ms: 10
        )

        findings = analyzer.analyze(context, config)
        finding = findings.find { |f| f.rule_name == :select_star }

        expect(finding.metadata).not_to be_empty
        expect(finding.metadata[:impact]).not_to be_nil
      end
    end

    context "multiple risks from single query" do
      before { config.analyze_query_risks = true }

      it "detects multiple risks in complex query" do
        context = QueryGuard::Core::Context.new
        context.add_query(
          sql: "SELECT * FROM users WHERE name LIKE '%test%'",
          name: "User.search",
          duration_ms: 150
        )

        findings = analyzer.analyze(context, config)

        # Should detect SELECT * and LIKE without index
        rule_names = findings.map(&:rule_name)
        expect(rule_names).to include(:select_star)
        expect(rule_names).to include(:like_without_index)
      end
    end
  end

  describe "#risk_title" do
    it "maps patterns to readable titles" do
      expect(analyzer.send(:risk_title, :select_star)).to eq("SELECT * Usage")
      expect(analyzer.send(:risk_title, :many_joins)).to eq("Complex Multi-Table Join")
      expect(analyzer.send(:risk_title, :repeated_query)).to eq("Repeated Query in Request")
      expect(analyzer.send(:risk_title, :potential_n_plus_one)).to eq("Potential N+1 Query Problem")
    end

    it "titleizes unknown patterns" do
      expect(analyzer.send(:risk_title, :unknown_pattern)).to eq("Unknown Pattern")
    end
  end

  describe "#risk_description" do
    it "maps patterns to descriptions" do
      desc = analyzer.send(:risk_description, :select_star)
      expect(desc).to include("unnecessary data")
    end

    it "includes actionable guidance" do
      desc = analyzer.send(:risk_description, :like_without_index)
      expect(desc).to include("full table scan")
    end
  end

  context "integration with config" do
    it "is registered in config analyzer registry" do
      config = QueryGuard::Config.new
      expect(config.analyzer_registry.get(:query_risk)).not_to be_nil
    end

    it "can be enabled and disabled" do
      config = QueryGuard::Config.new
      config.analyze_query_risks = false
      expect(config.analyze_query_risks).to be false

      config.analyze_query_risks = true
      expect(config.analyze_query_risks).to be true
    end
  end
end
