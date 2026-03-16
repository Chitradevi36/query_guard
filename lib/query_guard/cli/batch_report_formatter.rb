# frozen_string_literal: true

require 'json'
require 'time'

module QueryGuard
  class CLI
    # Formats multiple QueryGuard reports into a single batch request.
    #
    # Used for bulk ingestion into SaaS platforms. Supports:
    # - Multiple reports in a single API request
    # - Batch correlation IDs for tracking across the entire batch
    # - Per-report tracing for individual finding tracking
    # - Pagination metadata for large batches
    #
    # Example:
    #   reports = [
    #     { report_version: '1.0', findings: [...], ... },
    #     { report_version: '1.0', findings: [...], ... }
    #   ]
    #
    #   batch = BatchReportFormatter.new(
    #     reports: reports,
    #     batch_id: 'batch-123',
    #     correlation_id: 'api-request-456'
    #   )
    #
    #   json_output = batch.generate
    class BatchReportFormatter
      BATCH_SCHEMA_VERSION = '1.0'
      BATCH_TYPE = 'batch'

      def initialize(reports:, batch_id: nil, correlation_id: nil, options: {})
        @reports = Array(reports)
        @batch_id = batch_id || generate_batch_id
        @correlation_id = correlation_id || generate_correlation_id
        @options = options
        @created_at = Time.now
      end

      # Generate the complete batch JSON
      # Returns: String (JSON)
      def generate
        JSON.pretty_generate(build_batch)
      end

      # Build batch structure and return as hash
      def build_batch
        {
          batch_version: BATCH_SCHEMA_VERSION,
          batch_type: BATCH_TYPE,
          batch_id: @batch_id,
          correlation_id: @correlation_id,
          created_at: @created_at.utc.iso8601.gsub('+00:00', 'Z'),
          report_count: @reports.length,
          reports: @reports,
          pagination: build_pagination,
          stats: build_batch_stats
        }
      end

      private

      # Pagination metadata for large batches
      # Useful when records exceed size limits (e.g., >10MB)
      def build_pagination
        pagination = {
          total_reports: @reports.length,
          page: @options[:page] || 1,
          page_size: @options[:page_size] || @reports.length,
          has_more: @options[:has_more] || false
        }

        # Include continuation token if provided (for cursor-based pagination)
        pagination[:continuation_token] = @options[:continuation_token] if @options[:continuation_token]
        pagination[:next_page_token] = @options[:next_page_token] if @options[:next_page_token]

        pagination
      end

      # Aggregate statistics across all reports in the batch
      def build_batch_stats
        total_findings = 0
        total_critical = 0
        total_error = 0
        total_warn = 0
        total_info = 0
        by_report_type = { 'analyze' => 0, 'check' => 0 }

        @reports.each do |report|
          summary = report[:summary] || {}
          total_findings += summary[:total_findings] || 0
          total_critical += summary[:by_severity]&.dig(:critical) || 0
          total_error += summary[:by_severity]&.dig(:error) || 0
          total_warn += summary[:by_severity]&.dig(:warn) || 0
          total_info += summary[:by_severity]&.dig(:info) || 0

          report_type = report[:report_type] || 'unknown'
          by_report_type[report_type] ||= 0
          by_report_type[report_type] += 1
        end

        {
          total_findings: total_findings,
          findings_by_severity: {
            critical: total_critical,
            error: total_error,
            warn: total_warn,
            info: total_info
          },
          reports_by_type: by_report_type,
          processing_time_ms: ((@created_at - @created_at) * 1000).round(2)
        }
      end

      # Helper: Generate a unique batch ID
      def generate_batch_id
        require 'securerandom'
        "batch-#{SecureRandom.hex(8)}"
      end

      # Helper: Generate a correlation ID for the entire batch
      def generate_correlation_id
        require 'securerandom'
        "corr-#{SecureRandom.hex(8)}"
      end
    end
  end
end
