# frozen_string_literal: true

module QueryGuard
  module Migrations
    # Enhances risk analysis with table-size-aware context
    #
    # When database metadata is available, escalates risk severity
    # for operations on large tables.
    #
    # For example:
    # - add_index on 10M row table = CRITICAL (will lock for minutes)
    # - add_index on 100K row table = ERROR (will lock briefly)
    #
    # Works gracefully if database unavailable by falling back to
    # static analysis.
    class TableRiskAnalyzer
      # Risk escalation factors based on table size
      ESCALATION_FACTORS = {
        low: 0,        # < 1M rows: no escalation
        medium: 1,     # 1M - 10M rows: escalate 1 level (error -> critical)
        high: 2,       # 10M - 100M rows: escalate 2 levels (warn -> critical)
        critical: 3    # > 100M rows: already critical
      }.freeze

      # Initialize analyzer
      #
      # @param adapter [DatabaseAdapter] Optional database adapter
      def initialize(adapter = nil)
        @adapter = adapter || NullDatabaseAdapter.new
      end

      # Enhance risks with table size information
      #
      # @param migration_content [String] Migration file content
      # @param risks [Array<Hash>] Risks from MigrationRiskDetectors
      # @return [Array<Hash>] Risks with table metadata added
      def enhance_risks(migration_content, risks)
        return risks unless @adapter.connected?

        # Extract affected tables from migration
        affected_tables = TableSizeResolver.affected_tables(migration_content)
        return risks if affected_tables.empty?

        # Build table metadata cache
        table_metadata = {}
        affected_tables.each do |table_name|
          row_count = @adapter.estimate_table_rows(table_name)
          lock_risk = @adapter.estimate_lock_risk(table_name)

          table_metadata[table_name] = {
            estimated_rows: row_count,
            lock_risk: lock_risk
          }
        end

        # Enhance each risk with table metadata
        risks.map do |risk|
          enhance_single_risk(risk, migration_content, table_metadata)
        end
      end

      protected

      def enhance_single_risk(risk, migration_content, table_metadata)
        # Copy risk hash so we don't mutate original
        enhanced_risk = risk.dup
        metadata = (risk[:metadata] || {}).dup

        # Try to determine which table this risk refers to
        affected_tables = TableSizeResolver.affected_tables(migration_content)
        risk_type = risk[:type]

        # Different risk types affect different tables
        table_name = determine_risk_table(risk_type, migration_content, affected_tables)

        if table_name && table_metadata[table_name]
          table_info = table_metadata[table_name]

          # Add table metadata to risk
          metadata[:table_name] = table_name
          metadata[:estimated_table_rows] = table_info[:estimated_rows]
          metadata[:table_lock_risk] = table_info[:lock_risk]

          enhanced_risk[:metadata] = metadata

          # Escalate severity if table is large
          if table_info[:lock_risk]
            enhanced_risk = escalate_risk_for_table(enhanced_risk, table_info[:lock_risk])
            # Preserve our table metadata additions
            enhanced_risk[:metadata].merge!(metadata)
            enhanced_risk[:metadata][:severity_escalated] = true
            enhanced_risk[:metadata][:escalation_reason] = "Large table (#{format_row_count(table_info[:estimated_rows])} rows)"
          end
        else
          enhanced_risk[:metadata] = metadata
        end

        enhanced_risk
      end

      def determine_risk_table(risk_type, migration_content, affected_tables)
        # Heuristic: find the most likely table for this risk
        # Could be enhanced with more sophisticated analysis

        affected_tables.first # Simple: return first affected table for now
      end

      def escalate_risk_for_table(risk, lock_risk)
        return risk if lock_risk.nil?

        # Only escalate errors and warnings, not info
        return risk if risk[:severity] == :info

        escalation = ESCALATION_FACTORS[lock_risk] || 0
        return risk if escalation.zero?

        # Escalate severity based on table size
        escalated_risk = risk.dup
        original_severity = risk[:severity]

        escalated_risk[:severity] = case original_severity
                                   when :warn
                                     # Escalate WARN to ERROR for medium+ tables (escalation >= 1)
                                     escalation >= 1 ? :error : :warn
                                   when :error
                                     # Escalate ERROR to CRITICAL for medium+ tables (escalation >= 1)
                                     escalation >= 1 ? :critical : :error
                                   else
                                     original_severity
                                   end

        escalated_risk[:metadata] = (risk[:metadata] || {}).dup
        escalated_risk[:metadata][:original_severity] = original_severity

        escalated_risk
      end

      def format_row_count(count)
        return "unknown" if count.nil?

        case count
        when 0..999
          "#{count}"
        when 1000..999_999
          "#{(count / 1000.0).round(1)}K"
        when 1_000_000..999_999_999
          "#{(count / 1_000_000.0).round(1)}M"
        else
          "#{(count / 1_000_000_000.0).round(1)}B"
        end
      end
    end
  end
end
