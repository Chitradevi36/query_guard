# frozen_string_literal: true

module QueryGuard
  module Core
    # Immutable result of a rule analysis.
    # Represents a single violation or finding detected by an analyzer.
    #
    # A Finding encapsulates all information about a detected issue:
    # - What rule triggered (analyzer_name, rule_name)
    # - How severe it is (severity)
    # - Where it occurred (file_path, line_number, sql)
    # - Why it matters (title, description, recommendations)
    # - Context data (metadata)
    class Finding
      SEVERITIES = %i[info warn error].freeze

      # Core identification
      attr_reader :analyzer_name, :rule_name, :severity

      # Message and description (user-facing)
      attr_reader :title, :description, :message, :recommendations

      # Location information
      attr_reader :file_path, :line_number, :sql

      # Additional context
      attr_reader :metadata, :query, :created_at

      # Internal ID for tracking/deduplication
      attr_reader :id

      def initialize(
        analyzer_name:,
        rule_name:,
        severity: :warn,
        title: nil,
        description: nil,
        message: nil,
        file_path: nil,
        line_number: nil,
        sql: nil,
        metadata: {},
        query: nil,
        recommendations: []
      )
        @analyzer_name = analyzer_name.to_sym
        @rule_name = rule_name.to_sym
        @severity = validate_severity(severity)

        # Message handling: use title/description or fall back to message
        @title = title.to_s.freeze if title
        @description = description.to_s.freeze if description
        @message = (message || @title || "").to_s.freeze

        # Location info
        @file_path = file_path.to_s.freeze if file_path
        @line_number = line_number.to_i if line_number
        @sql = sql.to_s.freeze if sql

        # Recommendations
        @recommendations = Array(recommendations).map { |r| r.to_s.freeze }.freeze

        # Metadata
        @metadata = metadata.freeze
        @query = query
        @created_at = Time.now.freeze

        # Generate deterministic ID based on analyzer, rule, and sql for deduplication
        @id = generate_id
      end

      # Compare findings by key attributes
      def ==(other)
        other.is_a?(Finding) &&
          analyzer_name == other.analyzer_name &&
          rule_name == other.rule_name &&
          severity == other.severity &&
          message == other.message
      end

      # Hash based on ID for Set operations
      def hash
        id.hash
      end

      alias eql? ==

      # Serialize to hash for reporting/API
      # Useful for JSON output, CI integration, and telemetry
      def to_h
        {
          id: id,
          analyzer: analyzer_name,
          rule: rule_name,
          severity: severity,
          title: title,
          description: description,
          message: message,
          file_path: file_path,
          line_number: line_number,
          sql: sql,
          metadata: metadata,
          recommendations: recommendations,
          created_at: created_at&.iso8601,
          query: query&.to_h
        }.compact
      end

      # Serialize to JSON-friendly hash (excludes large/binary data)
      def to_json_h
        h = to_h
        # Optionally truncate SQL for JSON payloads
        h[:sql] = truncate_sql(h[:sql], 500) if h[:sql]
        h.except(:query) # Exclude full query object from JSON
      end

      # Human-readable string for logs
      def to_s
        "[#{severity.upcase}] #{analyzer_name}:#{rule_name} - #{message}"
      end

      # Detailed log format
      def to_log_s
        parts = [to_s]
        parts << "File: #{file_path}:#{line_number}" if file_path
        parts << "SQL: #{truncate_sql(sql, 100)}" if sql
        parts.join(" | ")
      end

      # Inspection string
      def inspect
        "#<Finding id=#{id[0, 8]} #{analyzer_name}:#{rule_name} severity=#{severity}>"
      end

      # Check if finding has location information
      def has_location?
        !file_path.nil?
      end

      private

      def generate_id
        # Simple deterministic ID: hash of analyzer:rule:sql
        content = "#{analyzer_name}:#{rule_name}:#{sql}:#{file_path}:#{line_number}"
        Digest::SHA256.hexdigest(content)[0, 16]
      end

      def truncate_sql(sql_text, length = 100)
        return sql_text if sql_text.nil? || sql_text.length <= length
        "#{sql_text[0, length]}..."
      end

      def validate_severity(sev)
        sym = sev.to_sym
        raise ArgumentError, "Invalid severity: #{sev}. Must be one of #{SEVERITIES}" unless SEVERITIES.include?(sym)
        sym
      end
    end
  end
end

require "digest"
