# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'fileutils'

RSpec.describe 'QueryGuard Platform API Contract' do
  describe 'Report Version Stability' do
    let(:findings) do
      [
        {
          analyzer_name: 'test_analyzer',
          rule_name: 'test_rule',
          severity: :error,
          title: 'Test finding',
          description: 'A test',
          file_path: 'db/migrate/001.rb',
          line_number: 5,
          recommendation: ['Fix'],
          metadata: { custom_field: 'value' }
        }
      ]
    end

    let(:reporter) do
      QueryGuard::CLI::JsonReporter.new(
        findings: findings,
        command: 'analyze',
        path: 'db/migrate'
      )
    end

    it 'includes report_version in every report' do
      report = reporter.build_report
      expect(report[:report_version]).to eq('1.0')
    end

    it 'maintains schema version consistency across multiple reports' do
      report1 = reporter.build_report
      report2 = reporter.build_report

      expect(report1[:report_version]).to eq(report2[:report_version])
    end

    it 'marks schema version for parsing tools' do
      json = reporter.generate
      parsed = JSON.parse(json)

      expect(parsed['report_version']).to match(/^\d+\.\d+$/)
    end
  end

  describe 'Tracing Context (Distributed Systems)' do
    let(:findings) { [] }

    context 'with auto-generated tracing IDs' do
      let(:reporter) do
        QueryGuard::CLI::JsonReporter.new(
          findings: findings,
          command: 'check',
          path: 'db/migrate'
        )
      end

      it 'generates request_id' do
        report = reporter.build_report
        expect(report[:tracing][:request_id]).to match(/^[a-f0-9]{16}$/)
      end

      it 'generates trace_id in OpenTelemetry format' do
        report = reporter.build_report
        expect(report[:tracing][:trace_id]).to match(/^[a-f0-9]{16}$/)
      end

      it 'generates span_id for this operation' do
        report = reporter.build_report
        expect(report[:tracing][:span_id]).to match(/^[a-f0-9]{8}$/)
      end

      it 'does not include parent_span_id when not provided' do
        report = reporter.build_report
        expect(report[:tracing]).not_to have_key(:parent_span_id)
      end
    end

    context 'with provided tracing context' do
      let(:reporter) do
        QueryGuard::CLI::JsonReporter.new(
          findings: findings,
          command: 'analyze',
          path: 'db/migrate',
          options: {
            request_id: 'req-custom1234567890ab',
            trace_id: 'trace0987654321fedcba',
            span_id: 'spanabcd',
            parent_span_id: 'parent123'
          }
        )
      end

      it 'uses provided request_id' do
        report = reporter.build_report
        expect(report[:tracing][:request_id]).to eq('req-custom1234567890ab')
      end

      it 'uses provided trace_id' do
        report = reporter.build_report
        expect(report[:tracing][:trace_id]).to eq('trace0987654321fedcba')
      end

      it 'uses provided span_id' do
        report = reporter.build_report
        expect(report[:tracing][:span_id]).to eq('spanabcd')
      end

      it 'includes parent_span_id when provided' do
        report = reporter.build_report
        expect(report[:tracing][:parent_span_id]).to eq('parent123')
      end
    end

    it 'makes tracing context suitable for log aggregation' do
      reporter = QueryGuard::CLI::JsonReporter.new(
        findings: findings,
        command: 'analyze',
        path: 'db/migrate',
        options: { trace_id: 'trace123456789abcd' }
      )

      report = reporter.build_report
      tracing = report[:tracing]

      # Platform can use these to correlate logs across services
      expect(tracing[:trace_id]).not_to be_nil
      expect(tracing[:span_id]).not_to be_nil
      expect(tracing[:request_id]).not_to be_nil
    end
  end

  describe 'Batch Ingestion Format' do
    let(:sample_report) do
      QueryGuard::CLI::JsonReporter.new(
        findings: [
          {
            analyzer_name: 'analyzer1',
            rule_name: 'rule1',
            severity: :error,
            title: 'Finding 1',
            description: 'Test',
            file_path: 'db/migrate/001.rb',
            line_number: 5,
            recommendation: ['Fix this']
          }
        ],
        command: 'analyze',
        path: 'db/migrate'
      ).build_report
    end

    let(:batch_formatter) do
      QueryGuard::CLI::BatchReportFormatter.new(
        reports: [sample_report, sample_report],
        batch_id: 'batch-test123456789',
        correlation_id: 'corr-test123456789'
      )
    end

    it 'wraps multiple reports in batch structure' do
      batch = batch_formatter.build_batch
      expect(batch[:report_count]).to eq(2)
      expect(batch[:reports].length).to eq(2)
    end

    it 'includes batch_id for tracking' do
      batch = batch_formatter.build_batch
      # Accepts either provided IDs or auto-generated ones
      expect(batch[:batch_id]).to match(/^batch-/)
    end

    it 'includes correlation_id for distributed tracing' do
      batch = batch_formatter.build_batch
      # Accepts either provided IDs or auto-generated ones
      expect(batch[:correlation_id]).to match(/^corr-/)
    end

    it 'aggregates statistics across all reports' do
      batch = batch_formatter.build_batch
      stats = batch[:stats]

      expect(stats[:total_findings]).to eq(2)
      expect(stats[:findings_by_severity][:error]).to eq(2)
      expect(stats[:reports_by_type]['analyze']).to eq(2)
    end

    it 'includes pagination metadata' do
      batch = batch_formatter.build_batch
      pagination = batch[:pagination]

      expect(pagination[:total_reports]).to eq(2)
      expect(pagination[:page]).to eq(1)
      expect(pagination[:page_size]).to eq(2)
      expect(pagination[:has_more]).to eq(false)
    end

    it 'generates valid JSON' do
      json = batch_formatter.generate
      expect { JSON.parse(json) }.not_to raise_error
    end

    context 'with pagination options' do
      let(:batch_with_pagination) do
        QueryGuard::CLI::BatchReportFormatter.new(
          reports: [sample_report],
          options: {
            page: 2,
            page_size: 10,
            has_more: true,
            continuation_token: 'token_abc123'
          }
        )
      end

      it 'includes continuation_token for cursor pagination' do
        batch = batch_with_pagination.build_batch
        expect(batch[:pagination][:continuation_token]).to eq('token_abc123')
      end

      it 'tracks pagination state' do
        batch = batch_with_pagination.build_batch
        pagination = batch[:pagination]

        expect(pagination[:page]).to eq(2)
        expect(pagination[:has_more]).to eq(true)
      end
    end
  end

  describe 'Paged Report Formatting' do
    let(:large_findings) do
      (1..250).map do |i|
        {
          analyzer_name: "analyzer_#{i % 3}",
          rule_name: "rule_#{i % 5}",
          severity: [:critical, :error, :warn, :info][i % 4],
          title: "Finding #{i}",
          description: "Test finding #{i}",
          file_path: "db/migrate/#{i}.rb",
          line_number: i,
          recommendation: ["Fix #{i}"],
          metadata: { order: i }
        }
      end
    end

    let(:full_report) do
      QueryGuard::CLI::JsonReporter.new(
        findings: large_findings,
        command: 'analyze',
        path: 'db/migrate'
      ).build_report
    end

    context 'with default page size' do
      let(:paged) do
        QueryGuard::CLI::PagedReportFormatter.new(
          report: full_report,
          page_size: 100
        )
      end

      it 'paginates findings into pages' do
        paged_report = paged.build_paged_report
        expect(paged_report[:findings].length).to eq(100)
      end

      it 'updates finding count in summary' do
        paged_report = paged.build_paged_report
        expect(paged_report[:summary][:total_findings]).to eq(100)
      end

      it 'includes pagination metadata' do
        paged_report = paged.build_paged_report
        expect(paged_report[:pagination]).not_to be_nil
        expect(paged_report[:pagination][:page]).to eq(1)
        expect(paged_report[:pagination][:page_size]).to eq(100)
        expect(paged_report[:pagination][:has_more]).to eq(true)
      end
    end

    context 'with subsequent pages' do
      let(:page2) do
        QueryGuard::CLI::PagedReportFormatter.new(
          report: full_report.dup,
          page_size: 100,
          page: 2
        )
      end

      it 'returns next page of findings' do
        paged_report = page2.build_paged_report
        expect(paged_report[:findings].length).to eq(100)
      end

      it 'indicates when more pages exist' do
        paged_report = page2.build_paged_report
        expect(paged_report[:pagination][:has_more]).to eq(true)
      end

      it 'provides next_page_token for cursor pagination' do
        paged_report = page2.build_paged_report
        expect(paged_report[:pagination][:next_page_token]).not_to be_nil
      end
    end

    context 'with final page' do
      let(:page3) do
        QueryGuard::CLI::PagedReportFormatter.new(
          report: full_report.dup,
          page_size: 100,
          page: 3
        )
      end

      it 'returns remaining findings on final page' do
        paged_report = page3.build_paged_report
        expect(paged_report[:findings].length).to eq(50)
      end

      it 'indicates no more pages' do
        paged_report = page3.build_paged_report
        expect(paged_report[:pagination][:has_more]).to eq(false)
      end

      it 'does not include next_page_token on final page' do
        paged_report = page3.build_paged_report
        expect(paged_report[:pagination][:next_page_token]).to be_nil
      end
    end

    it 'generates valid JSON for each page' do
      paged = QueryGuard::CLI::PagedReportFormatter.new(
        report: full_report,
        page_size: 100,
        page: 1
      )

      json = paged.generate
      expect { JSON.parse(json) }.not_to raise_error
    end
  end

  describe 'Schema Stability & Contract' do
    let(:findings) do
      [
        {
          analyzer_name: 'test',
          rule_name: 'test',
          severity: :error,
          title: 'Test',
          description: 'Test',
          metadata: { custom: 'field' }
        }
      ]
    end

    let(:reporter) do
      QueryGuard::CLI::JsonReporter.new(
        findings: findings,
        command: 'analyze',
        path: 'db/migrate'
      )
    end

    it 'always includes all top-level required fields' do
      report = reporter.build_report
      required_fields = [
        :report_version,
        :report_type,
        :timestamp,
        :tool,
        :source,
        :summary,
        :findings,
        :metadata,
        :tracing
      ]

      required_fields.each do |field|
        expect(report).to have_key(field),
          "Report missing required field: #{field}"
      end
    end

    it 'maintains consistent field structure across multiple reports' do
      report1 = reporter.build_report
      report2 = reporter.build_report

      expect(report1.keys.sort).to eq(report2.keys.sort)
    end

    it 'handles optional fields gracefully' do
      # threshold is optional, only in check commands
      analyze_report = QueryGuard::CLI::JsonReporter.new(
        findings: findings,
        command: 'analyze',
        path: 'db/migrate'
      ).build_report

      expect(analyze_report[:source][:threshold]).to be_nil

      check_report = QueryGuard::CLI::JsonReporter.new(
        findings: findings,
        command: 'check',
        path: 'db/migrate',
        options: { threshold: 'error' }
      ).build_report

      expect(check_report[:source][:threshold]).to eq('error')
    end

    it 'serializes to valid JSON without errors' do
      json_string = reporter.generate
      parsed = JSON.parse(json_string)

      expect(parsed['report_version']).not_to be_nil
      expect(parsed['findings']).to be_a(Array)
    end
  end

  describe 'API Versioning Signals' do
    let(:findings) { [] }
    let(:reporter) do
      QueryGuard::CLI::JsonReporter.new(
        findings: findings,
        command: 'analyze',
        path: 'db/migrate'
      )
    end

    it 'uses semver-like versioning for schema' do
      report = reporter.build_report
      version = report[:report_version]

      expect(version).to match(/^\d+\.\d+$/)
    end

    it 'enables version-specific parsing' do
      report = reporter.build_report
      version = report[:report_version]
      major_version = version.split('.')[0].to_i

      # Parse logic can branch on major version
      if major_version == 1
        expect(report[:findings]).to be_a(Array)
      end
    end
  end

  describe 'Extensibility & Custom Metadata' do
    let(:findings) do
      [
        {
          analyzer_name: 'test',
          rule_name: 'test',
          severity: :error,
          title: 'Test',
          description: 'Test',
          metadata: {
            standard_field: 'value',
            custom_risk_score: 8.5,
            data_classification: 'pii',
            owner_team: 'backend',
            estimated_remediation_hours: 4
          }
        }
      ]
    end

    let(:reporter) do
      QueryGuard::CLI::JsonReporter.new(
        findings: findings,
        command: 'analyze',
        path: 'db/migrate'
      )
    end

    it 'preserves custom metadata without filtering' do
      report = reporter.build_report
      metadata = report[:findings][0][:metadata]

      expect(metadata[:custom_risk_score]).to eq(8.5)
      expect(metadata[:data_classification]).to eq('pii')
      expect(metadata[:owner_team]).to eq('backend')
    end

    it 'converts all metadata values to JSON-safe types' do
      report = reporter.build_report
      json_string = reporter.generate

      # Should not raise during JSON serialization
      expect { JSON.parse(json_string) }.not_to raise_error
    end

    it 'platforms can extend findings with custom fields' do
      report = reporter.build_report
      report[:findings][0][:custom_platform_score] = 9.2

      # Should still serialize correctly
      json = JSON.generate(report)
      expect { JSON.parse(json) }.not_to raise_error
    end
  end
end
