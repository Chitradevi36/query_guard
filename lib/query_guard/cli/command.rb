# frozen_string_literal: true

module QueryGuard
  class CLI
    # Base class for CLI commands
    class Command
      def initialize(path, options = {})
        @path = path
        @options = options
        @formatter = Formatter.new(options)
      end

      protected

      def find_migration_files(path)
        pattern = File.join(path, '**', '*_*.rb')
        Dir.glob(pattern)
      end

      def find_ruby_files(path)
        pattern = File.join(path, '**', '*.rb')
        Dir.glob(pattern)
      end

      def analyze_migrations(files)
        analyzer = QueryGuard::Migrations::MigrationAnalyzer.new(
          database_adapter: get_database_adapter
        )

        findings = []
        files.each do |file|
          begin
            file_findings = analyzer.analyze_migration(file)
            file_findings.each do |finding|
              finding[:file] = file
              findings << finding
            end
          rescue => e
            puts "Warning: Failed to analyze #{file}: #{e.message}" if @options[:verbose]
          end
        end

        findings
      end

      def get_database_adapter
        # Try to get a live database adapter if available
        return nil unless defined?(ActiveRecord) && ActiveRecord::Base.connected?

        begin
          QueryGuard::Migrations::PostgreSQLAdapter.new(
            connection: ActiveRecord::Base.connection
          )
        rescue StandardError
          nil  # Fall back to NullDatabaseAdapter
        end
      end

      def severity_to_number(severity)
        case severity
        when :critical then 4
        when :error then 3
        when :warn then 2
        when :info then 1
        else 0
        end
      end

      def threshold_to_number(threshold)
        case threshold&.to_s&.downcase
        when 'critical' then 4
        when 'error' then 3
        when 'warn' then 2
        when 'info' then 1
        else 2  # Default to warn
        end
      end

      def findings_exceed_threshold?(findings, threshold)
        threshold_num = threshold_to_number(threshold)
        findings.any? { |f| severity_to_number(f[:severity]) >= threshold_num }
      end

      def path_exists?
        File.exist?(@path)
      end

      def path_absolute
        File.expand_path(@path)
      end
    end
  end
end
