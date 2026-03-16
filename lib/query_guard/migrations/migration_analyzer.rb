# frozen_string_literal: true

module QueryGuard
  module Migrations
    # Migration risk analyzer - scans Rails migration files for risky patterns.
    # Searches for dangerous operations like:
    # - Index additions without algorithm: :concurrently
    # - Column removals/type changes
    # - Non-NULL additions without defaults
    # - Full-table updates
    # - Unsafe raw SQL
    #
    # Optionally integrates with database metadata for table-size-aware risk estimation.
    #
    # Example:
    #   analyzer = MigrationAnalyzer.new
    #   findings = analyzer.analyze_migration(migration_file_path)
    #
    # With table size awareness:
    #   connection = ActiveRecord::Base.connection
    #   adapter = PostgreSQLAdapter.new(connection)
    #   analyzer = MigrationAnalyzer.new(database_adapter: adapter)
    #   findings = analyzer.analyze_migration(migration_file_path)
    class MigrationAnalyzer < Analyzers::Base
      # Initialize analyzer
      #
      # @param database_adapter [DatabaseAdapter] Optional adapter for table metadata
      def initialize(database_adapter: nil)
        super(:migration_risk)
        @database_adapter = database_adapter
        @table_risk_analyzer = TableRiskAnalyzer.new(database_adapter)
      end

      # Analyze a single migration file
      #
      # @param file_path [String] Path to migration file
      # @return [Array<Core::Finding>] List of findings
      def analyze_migration(file_path)
        return [] unless File.exist?(file_path)

        content = File.read(file_path)
        migration_name = File.basename(file_path, ".rb")

        risks = MigrationRiskDetectors.detect_risks(content, migration_name)
        
        # Enhance risks with table metadata if adapter available
        risks = @table_risk_analyzer.enhance_risks(content, risks)

        risks_to_findings(risks, file_path)
      end

      # Analyze all migrations in a directory
      #
      # @param migrations_dir [String] Path to db/migrate directory
      # @return [Array<Core::Finding>] List of findings from all migrations
      def analyze_migrations_directory(migrations_dir = "db/migrate")
        findings = []
        return findings unless Dir.exist?(migrations_dir)

        Dir.glob(File.join(migrations_dir, "*.rb")).each do |file_path|
          findings.concat(analyze_migration(file_path))
        end

        findings
      end

      # Analyze method for integration with QueryGuard context
      # This is called by registry when running full analysis
      #
      # @param context [Core::Context] Not used for migrations,  but required by Base
      # @param config [Config] Configuration object
      # @return [Array<Core::Finding>] List of findings
      def analyze(context, config)
        migrations_dir = config&.migrations_directory || "db/migrate"
        analyze_migrations_directory(migrations_dir)
      end

      private

      def risks_to_findings(risks, file_path)
        risks.map do |risk|
          severity = risk[:severity] || :warn

          Core::FindingBuilders.build(
            analyzer_name: name,
            rule_name: risk[:type],
            severity: severity,
            title: risk[:title],
            description: risk[:description],
            message: risk[:message],
            file_path: file_path,
            line_number: risk[:line_number],
            recommendations: [risk[:recommendation]],
            metadata: risk[:metadata]
          )
        end
      end
    end
  end
end
