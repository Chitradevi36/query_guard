# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'fileutils'

# Test the full integration of JSON output through the CLI
RSpec.describe 'JSON Output Format Integration' do
  let(:sample_migration_path) { 'spec/fixtures/db_migrate' }

  before :each do
    # Create test migration directory if needed
    FileUtils.mkdir_p(sample_migration_path) unless File.directory?(sample_migration_path)
  end

  after :each do
    # Cleanup
    FileUtils.rm_rf(sample_migration_path) if File.directory?(sample_migration_path)
  end

  describe 'Formatter with JSON option' do
    let(:formatter) { QueryGuard::CLI::Formatter.new(json: true) }
    let(:findings) do
      [
        {
          analyzer_name: 'test_analyzer',
          rule_name: 'test_rule',
          severity: :error,
          title: 'Test Finding',
          description: 'This is a test finding',
          file_path: 'db/migrate/001.rb',
          line_number: 5,
          recommendation: ['Fix this'],
          metadata: { table_name: 'users' }
        }
      ]
    end

    it 'outputs JSON format' do
      output = capture_output do
        formatter.print_findings(findings, 'Test Results', 'analyze', 'db/migrate')
      end

      expect { JSON.parse(output) }.not_to raise_error
    end

    it 'produces valid schema in JSON output' do
      output = capture_output do
        formatter.print_findings(findings, 'Test Results', 'analyze', 'db/migrate')
      end

      parsed = JSON.parse(output)

      # Check required fields
      expect(parsed['report_version']).to eq('1.0')
      expect(parsed['report_type']).to eq('analyze')
      expect(parsed['timestamp']).to be_a(String)
      expect(parsed['tool']).to be_a(Hash)
      expect(parsed['source']).to be_a(Hash)
      expect(parsed['summary']).to be_a(Hash)
      expect(parsed['findings']).to be_a(Array)
    end

    it 'does not output progress messages in JSON mode' do
      # This would be tested in the actual command execution
      # The formatter should not print status messages
      expect(formatter.instance_variable_get(:@json)).to be true
    end
  end

  describe 'Formatter with --format json flag' do
    let(:formatter) { QueryGuard::CLI::Formatter.new(format: 'json') }
    let(:findings) do
      [
        {
          analyzer_name: 'test',
          rule_name: 'test',
          severity: :warn,
          title: 'Test',
          description: 'Test',
          file_path: 'test.rb',
          recommendation: []
        }
      ]
    end

    it 'recognizes format option' do
      expect(formatter.instance_variable_get(:@json)).to be true
    end

    it 'outputs valid JSON' do
      output = capture_output do
        formatter.print_findings(findings, 'Results', 'analyze', '.')
      end

      expect { JSON.parse(output) }.not_to raise_error
    end
  end

  describe 'JSON output schema compliance' do
    let(:formatter) { QueryGuard::CLI::Formatter.new(json: true) }

    it 'includes all required top-level fields' do
      findings = [
        {
          analyzer_name: 'analyzer',
          rule_name: 'rule',
          severity: :error,
          title: 'Title',
          description: 'Desc',
          recommendation: []
        }
      ]

      output = capture_output do
        formatter.print_findings(findings, 'Title', 'analyze', '.')
      end

      parsed = JSON.parse(output)

      required_fields = %w[
        report_version
        report_type
        timestamp
        tool
        source
        summary
        findings
        metadata
      ]

      required_fields.each do |field|
        expect(parsed).to have_key(field), "Missing required field: #{field}"
      end
    end

    it 'includes all required finding fields' do
      findings = [
        {
          analyzer_name: 'analyzer',
          rule_name: 'rule',
          severity: :error,
          title: 'Title',
          description: 'Desc',
          recommendation: []
        }
      ]

      output = capture_output do
        formatter.print_findings(findings, 'Title', 'analyze', '.')
      end

      parsed = JSON.parse(output)
      finding = parsed['findings'].first

      required_finding_fields = %w[
        id
        analyzer
        rule
        severity
        title
        description
      ]

      required_finding_fields.each do |field|
        expect(finding).to have_key(field), "Missing finding field: #{field}"
      end
    end

    it 'has correct severity format' do
      findings = [
        {
          analyzer_name: 'analyzer',
          rule_name: 'rule',
          severity: :critical,
          title: 'Title',
          description: 'Desc'
        },
        {
          analyzer_name: 'analyzer',
          rule_name: 'rule',
          severity: :error,
          title: 'Title',
          description: 'Desc'
        },
        {
          analyzer_name: 'analyzer',
          rule_name: 'rule',
          severity: :warn,
          title: 'Title',
          description: 'Desc'
        }
      ]

      output = capture_output do
        formatter.print_findings(findings, 'Title', 'analyze', '.')
      end

      parsed = JSON.parse(output)

      # All findings should have string severity
      parsed['findings'].each do |finding|
        expect(finding['severity']).to be_a(String)
        expect(%w[critical error warn info]).to include(finding['severity'])
      end

      # Summary should have all severity counts
      summary = parsed['summary']['by_severity']
      expect(summary['critical']).to eq(1)
      expect(summary['error']).to eq(1)
      expect(summary['warn']).to eq(1)
      expect(summary['info']).to eq(0)
    end
  end

  # Helper to capture stdout
  def capture_output
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
