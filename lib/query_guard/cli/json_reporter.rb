# frozen_string_literal: true

require 'json'
require 'time'

module QueryGuard
  class CLI
    # Generates standardized JSON reports for QueryGuard analysis and check results.
    #
    # Provides a stable, versioned JSON schema suitable for:
    # - SaaS platform ingestion
    # - CI/CD integration
    # - External tool consumption
    # - Compliance and audit archival
    #
    # Schema version: 1.0 (documented in docs/JSON_REPORT_SCHEMA.md)
    #
    # Example:
    #   reporter = QueryGuard::CLI::JsonReporter.new(
    #     findings: findings,
    #     command: 'analyze',
    #     path: 'db/migrate',
    #     options: { threshold: 'error' }
    #   )
    #   json_output = reporter.generate
    class JsonReporter
      SCHEMA_VERSION = '1.0'
      TOOL_NAME = 'queryguard'

      def initialize(findings:, command:, path: '.', options: {})
        @findings = findings
        @command = command # 'analyze' or 'check'
        @path = path
        @options = options
        @started_at = Time.now

        # Initialize tracing context (for distributed systems)
        # Can be overridden via options: { request_id, trace_id, span_id, parent_span_id }
        @request_id = options[:request_id] || generate_request_id
        @trace_id = options[:trace_id] || generate_trace_id
        @span_id = options[:span_id] || generate_span_id
        @parent_span_id = options[:parent_span_id]

        # Initialize source metadata collector
        # Can be overridden via options: { source_metadata_collector }
        @source_metadata_collector = options[:source_metadata_collector] || SourceMetadataCollector.new
      end

      # Generate the complete JSON report
      # Returns: String (JSON)
      def generate
        JSON.pretty_generate(build_report)
      end

      # Generate report and return as parsed hash (useful for testing)
      def build_report
        {
          report_version: SCHEMA_VERSION,
          report_type: @command,
          timestamp: Time.now.utc.iso8601.gsub('+00:00', 'Z'),
          tool: build_tool,
          source: build_source,
          summary: build_summary,
          findings: build_findings,
          metadata: build_metadata,
          tracing: build_tracing
        }
      end

      private

      # Tool information block
      def build_tool
        {
          name: TOOL_NAME,
          version: QueryGuard::VERSION || 'unknown'
        }
      end

      # Source information (what was analyzed)
      def build_source
        source = {
          path: File.expand_path(@path),
          command: @command
        }

        # Include threshold for check command
        source[:threshold] = @options[:threshold] if @command == 'check' && @options[:threshold]

        # Include source metadata (git, CI provider information)
        source_metadata = @source_metadata_collector.collect
        if source_metadata
          source[:metadata] = source_metadata
        end

        source
      end

      # Summary statistics
      def build_summary
        by_severity = @findings.group_by { |f| f[:severity] || :info }

        {
          total_findings: @findings.length,
          by_severity: {
            critical: (by_severity[:critical] || []).length,
            error: (by_severity[:error] || []).length,
            warn: (by_severity[:warn] || []).length,
            info: (by_severity[:info] || []).length
          },
          files_analyzed: unique_files_count,
          files_with_findings: unique_files_with_findings_count
        }
      end

      # Array of finding objects
      def build_findings
        @findings.map do |finding|
          {
            id: finding[:id] || generate_finding_id(finding),
            analyzer: finding[:analyzer_name] || finding[:analyzer] || 'unknown',
            rule: finding[:rule_name] || finding[:rule] || 'unknown',
            severity: (finding[:severity] || :info).to_s,
            title: finding[:title] || finding[:message] || '(no title)',
            description: finding[:description] || '',
            file_path: finding[:file_path],
            line_number: finding[:line_number],
            recommendation: clean_recommendations(finding[:recommendation]),
            metadata: clean_metadata(finding[:metadata])
          }.compact # Remove nil values
        end
      end

      # Additional metadata about the analysis
      def build_metadata
        {
          total_files_checked: unique_files_count,
          has_index_suggestions: findings_have_index_suggestions?,
          has_migration_steps: findings_have_migration_steps?,
          execution_time_ms: ((Time.now - @started_at) * 1000).round(2)
        }
      end

      # Tracing context for distributed systems (OpenTelemetry compatible)
      def build_tracing
        tracing = {
          request_id: @request_id,
          trace_id: @trace_id,
          span_id: @span_id
        }

        tracing[:parent_span_id] = @parent_span_id if @parent_span_id

        tracing
      end

      # Helper: Count unique files analyzed
      def unique_files_count
        @findings.map { |f| f[:file_path] }.compact.uniq.length
      end

      # Helper: Count unique files that have findings
      def unique_files_with_findings_count
        @findings.map { |f| f[:file_path] }.compact.uniq.length
      end

      # Helper: Do any findings have index suggestions?
      def findings_have_index_suggestions?
        return false if @findings.empty?

        @findings.any? do |f|
          metadata = f[:metadata] || {}
          metadata[:index_sql] || metadata[:suggested_indexes]
        end
      end

      # Helper: Do any findings have migration steps?
      def findings_have_migration_steps?
        return false if @findings.empty?

        @findings.any? do |f|
          metadata = f[:metadata] || {}
          metadata[:migration_steps]
        end
      end

      # Helper: Ensure recommendations are an array of strings
      def clean_recommendations(recommendations)
        return nil if recommendations.nil? || recommendations.empty?

        Array(recommendations).map(&:to_s)
      end

      # Helper: Clean metadata, ensure it doesn't leak internal objects
      def clean_metadata(metadata)
        return nil if metadata.nil? || metadata.empty?

        # Convert metadata hash to a clean version
        # Remove any Ruby objects that won't serialize to JSON
        clean_hash(metadata)
      end

      # Helper: Recursively clean a hash for JSON serialization
      def clean_hash(hash)
        hash.transform_values do |value|
          case value
          when Hash
            clean_hash(value)
          when Array
            value.map { |v| v.is_a?(Hash) ? clean_hash(v) : v.to_s }
          when String, Numeric, TrueClass, FalseClass, NilClass
            value
          else
            # Convert unknown objects to string representation
            value.to_s
          end
        end
      end

      # Helper: Generate deterministic ID for a finding
      def generate_finding_id(finding)
        require 'digest'

        content = "#{finding[:analyzer_name]}:#{finding[:rule_name]}:#{finding[:file_path]}:#{finding[:line_number]}"
        Digest::SHA256.hexdigest(content)[0, 16]
      end

      # Helper: Generate a request ID (UUID-like format)
      def generate_request_id
        require 'securerandom'
        SecureRandom.hex(8)
      end

      # Helper: Generate a trace ID for distributed tracing (16 hex chars, 64-bit)
      def generate_trace_id
        require 'securerandom'
        SecureRandom.hex(8)
      end

      # Helper: Generate a span ID (8 hex chars, 32-bit)
      def generate_span_id
        require 'securerandom'
        SecureRandom.hex(4)
      end
    end
  end
end
