# frozen_string_literal: true

module QueryGuard
  class CLI
    module Commands
      # Analyzes queries and migrations, printing detailed results
      class Analyze < Command
        def execute
          unless path_exists?
            puts "Error: Path does not exist: #{path_absolute}"
            exit 1
          end

          # Skip progress output if JSON format is being used
          unless @options[:json] || @options[:format] == 'json'
            puts "Analyzing: #{path_absolute}"
            
            # Show database context
            adapter = get_database_adapter
            if adapter
              puts "Database context: Connected (accurate severity)\n"
            else
              puts "Database context: Not available (conservative estimates)"
              puts "  For more accurate results, run: DATABASE_URL=... queryguard analyze\n"
            end
            
            puts "(This may take a moment...)\n"
          end

          # Find and analyze migration files
          migration_files = find_migration_files(@path)
          if migration_files.any?
            puts "  Found #{migration_files.length} migration files" unless @options[:json] || @options[:format] == 'json'
            findings = analyze_migrations(migration_files)
          else
            findings = []
          end

          # Format and print results
          if findings.any?
            @formatter.print_findings(findings, "Migration Risk Analysis Results", 'analyze', @path)
          else
            puts "\n✅ No issues found in migrations!\n" unless @options[:json] || @options[:format] == 'json'
          end

          # Exit with success (analyze doesn't fail on findings)
          0
        end
      end
    end
  end
end
