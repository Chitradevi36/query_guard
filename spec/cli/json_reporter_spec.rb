# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe QueryGuard::CLI::JsonReporter do
  describe '#build_report' do
    let(:findings) do
      [
        {
          analyzer_name: 'query_risk_analyzer',
          rule_name: 'remove_column',
          severity: :error,
          title: 'Removing column detected',
          description: 'Removing columns can result in data loss',
          file_path: 'db/migrate/001_test.rb',
          line_number: 5,
          recommendation: ['Use reversible migration'],
          metadata: { table_name: 'users', estimated_table_rows: 15000 }
        },
        {
          analyzer_name: 'query_risk_analyzer',
          rule_name: 'select_star',
          severity: :warn,
          title: 'SELECT * detected',
          description: 'SELECT * can be inefficient',
          file_path: 'db/migrate/002_test.rb',
          line_number: 10,
          recommendation: [],
          metadata: nil
        }
      ]
    end

    let(:reporter) do
      QueryGuard::CLI::JsonReporter.new(
        findings: findings,
        command: 'analyze',
        path: 'db/migrate',
        options: {}
      )
    end

    it 'generates a valid JSON report' do
      report = reporter.build_report
      expect(report).to be_a(Hash)
    end

    describe 'report_version' do
      it 'includes schema version' do
        report = reporter.build_report
        expect(report[:report_version]).to eq('1.0')
      end

      it 'is a stable version' do
        report = reporter.build_report
        expect(report[:report_version]).to match(/^\d+\.\d+$/)
      end
    end

    describe 'report_type' do
      it 'matches the command' do
        report = reporter.build_report
        expect(report[:report_type]).to eq('analyze')
      end

      context 'with check command' do
        let(:reporter) do
          QueryGuard::CLI::JsonReporter.new(
            findings: findings,
            command: 'check',
            path: 'db/migrate',
            options: { threshold: 'error' }
          )
        end

        it 'shows check as report type' do
          report = reporter.build_report
          expect(report[:report_type]).to eq('check')
        end
      end
    end

    describe 'timestamp' do
      it 'includes ISO8601 timestamp' do
        report = reporter.build_report
        expect(report[:timestamp]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
      end

      it 'is a valid timestamp' do
        report = reporter.build_report
        expect { Time.iso8601(report[:timestamp]) }.not_to raise_error
      end
    end

    describe 'tool object' do
      it 'includes tool information' do
        report = reporter.build_report
        expect(report[:tool]).to be_a(Hash)
        expect(report[:tool][:name]).to eq('queryguard')
        expect(report[:tool][:version]).to be_a(String)
      end
    end

    describe 'source object' do
      it 'includes source path' do
        report = reporter.build_report
        expect(report[:source][:path]).to include('db/migrate')
      end

      it 'includes command' do
        report = reporter.build_report
        expect(report[:source][:command]).to eq('analyze')
      end

      context 'with check command' do
        let(:reporter) do
          QueryGuard::CLI::JsonReporter.new(
            findings: findings,
            command: 'check',
            path: 'db/migrate',
            options: { threshold: 'error' }
          )
        end

        it 'includes threshold for check command' do
          report = reporter.build_report
          expect(report[:source][:threshold]).to eq('error')
        end
      end

      it 'does not include threshold for analyze command' do
        report = reporter.build_report
        expect(report[:source].keys).not_to include(:threshold)
      end

      describe 'with source metadata' do
        it 'includes CI metadata when collector provides it' do
          mock_collector = double('SourceMetadataCollector')
          allow(mock_collector).to receive(:collect).and_return({
            git: { sha: 'abc123', branch: 'main' },
            ci: { provider: 'github_actions', ci: true }
          })

          reporter = QueryGuard::CLI::JsonReporter.new(
            findings: findings,
            command: 'analyze',
            path: 'db/migrate',
            options: { source_metadata_collector: mock_collector }
          )

          report = reporter.build_report
          expect(report[:source][:metadata][:git][:sha]).to eq('abc123')
          expect(report[:source][:metadata][:git][:branch]).to eq('main')
          expect(report[:source][:metadata][:ci][:provider]).to eq('github_actions')
        end

        it 'does not include metadata key when collector returns empty' do
          mock_collector = double('SourceMetadataCollector')
          allow(mock_collector).to receive(:collect).and_return(nil)

          reporter = QueryGuard::CLI::JsonReporter.new(
            findings: findings,
            command: 'analyze',
            path: 'db/migrate',
            options: { source_metadata_collector: mock_collector }
          )

          report = reporter.build_report
          expect(report[:source].key?(:metadata)).to be false
        end

        it 'includes git information in metadata' do
          mock_collector = double('SourceMetadataCollector')
          allow(mock_collector).to receive(:collect).and_return({
            git: { sha: 'def456', branch: 'feature/test', repository: 'query_guard' }
          })

          reporter = QueryGuard::CLI::JsonReporter.new(
            findings: findings,
            command: 'analyze',
            path: 'db/migrate',
            options: { source_metadata_collector: mock_collector }
          )

          report = reporter.build_report
          expect(report[:source][:metadata][:git][:sha]).to eq('def456')
          expect(report[:source][:metadata][:git][:branch]).to eq('feature/test')
          expect(report[:source][:metadata][:git][:repository]).to eq('query_guard')
        end

        it 'includes CI provider information' do
          mock_collector = double('SourceMetadataCollector')
          allow(mock_collector).to receive(:collect).and_return({
            ci: {
              provider: 'circle_ci',
              ci: true,
              repository_owner: 'owner',
              repository_name: 'repo',
              build_number: '123'
            }
          })

          reporter = QueryGuard::CLI::JsonReporter.new(
            findings: findings,
            command: 'analyze',
            path: 'db/migrate',
            options: { source_metadata_collector: mock_collector }
          )

          report = reporter.build_report
          expect(report[:source][:metadata][:ci][:provider]).to eq('circle_ci')
          expect(report[:source][:metadata][:ci][:repository_owner]).to eq('owner')
          expect(report[:source][:metadata][:ci][:build_number]).to eq('123')
        end

        it 'includes PR information when available' do
          mock_collector = double('SourceMetadataCollector')
          allow(mock_collector).to receive(:collect).and_return({
            ci: {
              provider: 'github_actions',
              ci: true,
              pull_request: true,
              pull_request_number: 42
            }
          })

          reporter = QueryGuard::CLI::JsonReporter.new(
            findings: findings,
            command: 'analyze',
            path: 'db/migrate',
            options: { source_metadata_collector: mock_collector }
          )

          report = reporter.build_report
          expect(report[:source][:metadata][:ci][:pull_request]).to eq(true)
          expect(report[:source][:metadata][:ci][:pull_request_number]).to eq(42)
        end
      end
    end

    describe 'summary object' do
      it 'includes total count' do
        report = reporter.build_report
        expect(report[:summary][:total_findings]).to eq(2)
      end

      it 'counts findings by severity' do
        report = reporter.build_report
        expect(report[:summary][:by_severity][:error]).to eq(1)
        expect(report[:summary][:by_severity][:warn]).to eq(1)
      end

      it 'includes all severity levels' do
        report = reporter.build_report
        expect(report[:summary][:by_severity].keys).to include(:critical, :error, :warn, :info)
      end

      it 'counts unique files analyzed' do
        report = reporter.build_report
        expect(report[:summary][:files_analyzed]).to be >= 2
      end

      it 'counts files with findings' do
        report = reporter.build_report
        expect(report[:summary][:files_with_findings]).to be >= 1
      end
    end

    describe 'findings array' do
      it 'includes each finding' do
        report = reporter.build_report
        expect(report[:findings].length).to eq(2)
      end

      it 'includes required finding fields' do
        report = reporter.build_report
        finding = report[:findings].first

        expect(finding[:id]).to be_a(String)
        expect(finding[:analyzer]).to be_a(String)
        expect(finding[:rule]).to be_a(String)
        expect(finding[:severity]).to be_a(String)
        expect(finding[:title]).to be_a(String)
        expect(finding[:description]).to be_a(String)
      end

      it 'includes optional finding fields when present' do
        report = reporter.build_report
        finding = report[:findings].first

        expect(finding[:file_path]).to be_a(String)
        expect(finding[:line_number]).to be_a(Integer)
      end

      it 'does not include optional fields if nil' do
        finding_without_path = {
          analyzer_name: 'test',
          rule_name: 'test',
          severity: :info,
          title: 'Test',
          description: 'Test',
          file_path: nil,
          line_number: nil,
          recommendation: []
        }

        reporter = QueryGuard::CLI::JsonReporter.new(
          findings: [finding_without_path],
          command: 'analyze',
          path: 'db/migrate'
        )

        report = reporter.build_report
        finding = report[:findings].first

        expect(finding.key?(:file_path)).to be false
        expect(finding.key?(:line_number)).to be false
      end

      it 'includes recommendations as array' do
        report = reporter.build_report
        finding = report[:findings].first

        expect(finding[:recommendation]).to be_a(Array)
        expect(finding[:recommendation].first).to be_a(String)
      end

      it 'converts recommendations to strings' do
        finding_with_symbols = {
          analyzer_name: 'test',
          rule_name: 'test',
          severity: :info,
          title: 'Test',
          description: 'Test',
          recommendation: [:fix_this, :and_that]
        }

        reporter = QueryGuard::CLI::JsonReporter.new(
          findings: [finding_with_symbols],
          command: 'analyze',
          path: 'db/migrate'
        )

        report = reporter.build_report
        finding = report[:findings].first

        expect(finding[:recommendation]).to eq(['fix_this', 'and_that'])
      end

      it 'includes clean metadata' do
        report = reporter.build_report
        finding = report[:findings].first

        expect(finding[:metadata][:table_name]).to eq('users')
        expect(finding[:metadata][:estimated_table_rows]).to eq(15000)
      end
    end

    describe 'metadata object' do
      it 'includes execution time' do
        report = reporter.build_report
        expect(report[:metadata][:execution_time_ms]).to be_a(Numeric)
        expect(report[:metadata][:execution_time_ms]).to be >= 0
      end

      it 'includes file statistics' do
        report = reporter.build_report
        expect(report[:metadata][:total_files_checked]).to be >= 2
        expect(report[:metadata][:has_index_suggestions]).to be_a(TrueClass).or be_a(FalseClass)
        expect(report[:metadata][:has_migration_steps]).to be_a(TrueClass).or be_a(FalseClass)
      end
    end

    describe 'JSON serialization' do
      it 'generates valid JSON' do
        json_string = reporter.generate
        expect { JSON.parse(json_string) }.not_to raise_error
      end

      it 'produces pretty-printed JSON' do
        json_string = reporter.generate
        # Check for indentation
        expect(json_string).to match(/\n  /)
      end

      it 'includes special characters correctly' do
        finding_with_special_chars = {
          analyzer_name: 'test',
          rule_name: 'test',
          severity: :info,
          title: 'Test "quoted" & special <chars>',
          description: 'Test',
          recommendation: ['Use "quoted" values']
        }

        reporter = QueryGuard::CLI::JsonReporter.new(
          findings: [finding_with_special_chars],
          command: 'analyze',
          path: 'db/migrate'
        )

        json_string = reporter.generate
        parsed = JSON.parse(json_string)

        expect(parsed['findings'].first['title']).to include('quoted')
        expect(parsed['findings'].first['recommendation'].first).to include('quoted')
      end
    end
  end

  describe 'schema stability' do
    it 'maintains consistent finding ID format' do
      finding1 = {
        analyzer_name: 'test',
        rule_name: 'test_rule',
        severity: :info,
        title: 'Test',
        description: 'Test',
        file_path: 'test.rb',
        line_number: 1
      }

      reporter1 = QueryGuard::CLI::JsonReporter.new(
        findings: [finding1],
        command: 'analyze',
        path: '.'
      )

      reporter2 = QueryGuard::CLI::JsonReporter.new(
        findings: [finding1],
        command: 'analyze',
        path: '.'
      )

      report1 = reporter1.build_report
      report2 = reporter2.build_report

      # Same input should produce same ID (deterministic)
      expect(report1[:findings].first[:id]).to eq(report2[:findings].first[:id])
    end

    it 'generates short IDs for deduplication' do
      finding = {
        analyzer_name: 'test',
        rule_name: 'test',
        severity: :info,
        title: 'Test',
        description: 'Test'
      }

      reporter = QueryGuard::CLI::JsonReporter.new(
        findings: [finding],
        command: 'analyze',
        path: '.'
      )

      report = reporter.build_report
      finding_id = report[:findings].first[:id]

      # ID should be relatively short (first 16 chars of SHA256)
      expect(finding_id.length).to eq(16)
    end
  end

  describe 'edge cases' do
    it 'handles empty findings' do
      reporter = QueryGuard::CLI::JsonReporter.new(
        findings: [],
        command: 'analyze',
        path: 'db/migrate'
      )

      report = reporter.build_report

      expect(report[:summary][:total_findings]).to eq(0)
      expect(report[:findings]).to eq([])
    end

    it 'handles findings with no metadata' do
      finding = {
        analyzer_name: 'test',
        rule_name: 'test',
        severity: :info,
        title: 'Test',
        description: 'Test',
        metadata: nil
      }

      reporter = QueryGuard::CLI::JsonReporter.new(
        findings: [finding],
        command: 'analyze',
        path: '.'
      )

      report = reporter.build_report
      json_string = reporter.generate

      expect { JSON.parse(json_string) }.not_to raise_error
      expect(report[:findings].first.key?(:metadata)).to be false
    end

    it 'handles findings with empty recommendations' do
      finding = {
        analyzer_name: 'test',
        rule_name: 'test',
        severity: :info,
        title: 'Test',
        description: 'Test',
        recommendation: []
      }

      reporter = QueryGuard::CLI::JsonReporter.new(
        findings: [finding],
        command: 'analyze',
        path: '.'
      )

      report = reporter.build_report
      # Empty recommendations should not appear in output
      expect(report[:findings].first.key?(:recommendation)).to be false
    end

    it 'cleans complex metadata objects' do
      # Simulate metadata with complex objects that shouldn't be in JSON
      finding = {
        analyzer_name: 'test',
        rule_name: 'test',
        severity: :info,
        title: 'Test',
        description: 'Test',
        metadata: {
          simple_string: 'value',
          simple_number: 42,
          nested_hash: { key: 'value' },
          nested_array: [1, 2, 3]
        }
      }

      reporter = QueryGuard::CLI::JsonReporter.new(
        findings: [finding],
        command: 'analyze',
        path: '.'
      )

      json_string = reporter.generate
      parsed = JSON.parse(json_string)

      # Should parse successfully with no Ruby objects
      expect(parsed['findings'].first['metadata']).to be_a(Hash)
      expect { JSON.generate(parsed) }.not_to raise_error
    end
  end
end
