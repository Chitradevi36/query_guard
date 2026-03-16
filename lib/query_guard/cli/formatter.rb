# frozen_string_literal: true

module QueryGuard
  class CLI
    # Formats findings for terminal output or JSON
    # Provides clean, developer-friendly output with:
    # - Severity and type grouping
    # - Clear recommendations and action items
    # - Index suggestions and migration steps
    # - Summary with detailed counts
    class Formatter
      def initialize(options = {})
        @options = options
        @json = options[:json] || options[:format] == 'json' || false
        @verbose = options[:verbose] || false
      end

      def print_findings(findings, title = "Analysis Results", command = 'analyze', path = '.')
        if @json
          print_json(findings, command, path)
        else
          print_text(findings, title)
        end
      end

      def print_text(findings, title)
        puts "\n" + "=" * 60
        puts title
        puts "=" * 60

        if findings.empty?
          puts "\n✅ No issues found!\n"
          return
        end

        # Group findings by severity, then by type
        by_severity = findings.group_by { |f| f[:severity] }

        # Print in order
        severity_order = [:critical, :error, :warn, :info]
        severity_order.each do |severity|
          next unless by_severity[severity]

          print_severity_section(severity, by_severity[severity])
        end

        print_summary(findings)
      end

      def print_severity_section(severity, findings)
        icon = severity_icon(severity)
        color = severity_color(severity)
        label = severity.to_s.upcase

        puts "\n#{icon}  #{color}#{label}#{reset_color} (#{findings.length})"
        puts "-" * 60

        # Group by type within severity
        by_type = findings.group_by { |f| "#{f[:analyzer_name]}:#{f[:rule_name]}" }

        by_type.each do |type_key, type_findings|
          print_type_group(type_key, type_findings)
        end
      end

      def print_type_group(type_key, findings)
        # Print type header when multiple findings of same type
        if findings.length == 1
          print_finding(findings.first)
        else
          puts "\n  [#{type_key}] (#{findings.length} findings)"
          findings.each do |finding|
            print_finding(finding, indent: "    ")
          end
        end
      end

      def print_finding(finding, indent: "  ")
        # Title and location
        puts "\n#{indent}#{finding[:title]}"

        # File and line info
        if finding[:file_path]
          location = "#{finding[:file_path]}"
          location += ":#{finding[:line_number]}" if finding[:line_number]
          puts "#{indent}  📄 #{location}"
        end

        # Description
        if finding[:description]
          puts "#{indent}  #{finding[:description]}"
        end

        # Metadata context (table, operation, escalation)
        print_finding_context(finding, indent)

        # Recommendations (primary)
        print_recommendations(finding, indent)

        # Special metadata sections: indexes, migration steps, strategies
        print_index_suggestions(finding, indent)
        print_migration_steps(finding, indent)

        # Verbose debug metadata
        if @verbose && finding[:metadata] && !finding[:metadata].empty?
          puts "#{indent}  [Debug] #{finding[:metadata].inspect}"
        end
      end

      def print_finding_context(finding, indent)
        metadata = finding[:metadata] || {}

        # Table context
        if metadata[:table_name]
          rows = metadata[:estimated_table_rows]
          rows_str = rows ? " (#{format_row_count(rows)} rows)" : ""
          puts "#{indent}  🗂️  Table: #{metadata[:table_name]}#{rows_str}"
        end

        # Operation context
        if metadata[:operation]
          puts "#{indent}  ⚙️  Operation: #{metadata[:operation]}"
        end

        # Escalation
        if metadata[:severity_escalated]
          original = metadata[:original_severity]
          reason = metadata[:escalation_reason]
          puts "#{indent}  ⬆️  Escalated from #{original}: #{reason}"
        end

        # Risk level
        if metadata[:risk_level]
          puts "#{indent}  Risk Level: #{metadata[:risk_level]}"
        end
      end

      def print_recommendations(finding, indent)
        # Show recommendations as action items
        recommendations = Array(finding[:recommendation])

        if recommendations.any?
          puts "#{indent}  ✅ Recommended Actions:"
          recommendations.each do |rec|
            puts "#{indent}     - #{rec}"
          end
        end
      end

      def print_index_suggestions(finding, indent)
        metadata = finding[:metadata] || {}

        # Check for single index suggestion
        if metadata[:index_sql]
          puts "#{indent}  🔧 Suggested Index:"
          puts "#{indent}     #{metadata[:index_sql]}"
        elsif metadata[:suggested_indexes]
          # Multiple index suggestions
          puts "#{indent}  🔧 Suggested Indexes:"
          Array(metadata[:suggested_indexes]).each do |idx_sql|
            puts "#{indent}     #{idx_sql}"
          end
        end
      end

      def print_migration_steps(finding, indent)
        metadata = finding[:metadata] || {}

        # Migration step-by-step guidance
        if metadata[:migration_steps]
          puts "#{indent}  📋 Migration Steps:"
          Array(metadata[:migration_steps]).each_with_index do |step, i|
            puts "#{indent}     #{i + 1}. #{step}"
          end
        end

        # Safe rollout strategy
        if metadata[:safe_rollout_strategy]
          puts "#{indent}  🛡️  Safe Rollout Strategy:"
          puts "#{indent}     #{metadata[:safe_rollout_strategy]}"
        end
      end

      def print_json(findings, command = 'analyze', path = '.')
        reporter = JsonReporter.new(
          findings: findings,
          command: command,
          path: path,
          options: @options
        )
        puts reporter.generate
      end

      private

      def print_summary(findings)
        by_severity = findings.group_by { |f| f[:severity] }
        severity_counts = by_severity.transform_values { |v| v.length }

        # Count by type
        by_type = findings.group_by { |f| "#{f[:analyzer_name]}:#{f[:rule_name]}" }
        type_counts = by_type.transform_values { |v| v.length }

        puts "\n" + "=" * 60
        puts "SUMMARY"
        puts "=" * 60

        # Total
        puts "\n  Total Findings: #{findings.length}"

        # By Severity
        puts "\n  By Severity:"
        %i[critical error warn info].each do |severity|
          count = severity_counts[severity] || 0
          next if count.zero?

          icon = severity_icon(severity)
          puts "    #{icon} #{severity.to_s.upcase}: #{count}"
        end

        # By Type (if more than one)
        if type_counts.length > 1
          puts "\n  By Type:"
          type_counts.sort_by { |_k, v| -v }.each do |type_key, count|
            puts "    • #{type_key}: #{count}"
          end
        end

        # Quick stats
        puts "\n  Files Analyzed:"
        files_with_findings = findings.group_by { |f| f[:file_path] }.keys.compact.length
        puts "    • #{files_with_findings} file#{files_with_findings == 1 ? '' : 's'} with findings"

        puts "\n" + "=" * 60 + "\n"
      end

      def severity_icon(severity)
        case severity
        when :critical then "🚨"
        when :error then "❌"
        when :warn then "⚠️ "
        when :info then "ℹ️ "
        else "•"
        end
      end

      def severity_color(severity)
        # ANSI color codes
        case severity
        when :critical then "\e[31m"     # Red
        when :error then "\e[31m"        # Red
        when :warn then "\e[33m"         # Yellow
        when :info then "\e[34m"         # Blue
        else ""
        end
      end

      def reset_color
        "\e[0m"
      end

      def format_row_count(count)
        return "unknown" if count.nil?

        case count
        when 0..999
          "#{count}"
        when 1_000..999_999
          "#{(count / 1_000.0).round(1)}K"
        when 1_000_000..999_999_999
          "#{(count / 1_000_000.0).round(1)}M"
        else
          "#{(count / 1_000_000_000.0).round(1)}B"
        end
      end
    end
  end
end
