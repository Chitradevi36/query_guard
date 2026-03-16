# frozen_string_literal: true

module QueryGuard
  class CLI
    module Commands
      # Checks if findings exceed severity threshold for CI/CD
      class Check < Command
        def execute
          unless path_exists?
            puts "Error: Path does not exist: #{path_absolute}"
            return 2  # Failed to check
          end

          threshold = @options[:threshold] || 'error'

          # Skip progress output if JSON format is being used
          unless @options[:json] || @options[:format] == 'json'
            puts "Checking migrations: #{path_absolute}"
            puts "Threshold: #{threshold.upcase}\n"
            puts "(This may take a moment...)\n"
          end

          # Find and analyze migration files
          migration_files = find_migration_files(@path)
          if migration_files.empty?
            puts "✅ No migrations found - clear to deploy!\n" unless @options[:json] || @options[:format] == 'json'
            return 0
          end

          puts "  Found #{migration_files.length} migration files" unless @options[:json] || @options[:format] == 'json'
          findings = analyze_migrations(migration_files)

          if findings.empty?
            puts "\n✅ No issues found - clear to deploy!\n" unless @options[:json] || @options[:format] == 'json'
            return 0
          end

          # Check if findings exceed threshold
          if findings_exceed_threshold?(findings, threshold)
            @formatter.print_findings(findings, "Migration Risk Check - FAILED ❌", 'check', @path)
            unless @options[:json] || @options[:format] == 'json'
              puts "\n🚫 Risk threshold exceeded! Deployment blocked.\n"
              puts "To proceed, either:"
              puts "  1. Fix the identified risks above"
              puts "  2. Increase the threshold (e.g., --threshold error)"
              puts "  3. Review with your DBA\n"
            end
            return 1  # Check failed
          else
            @formatter.print_findings(findings, "Migration Risk Check - PASSED ✅", 'check', @path)
            puts "\n✅ All risks below threshold - clear to deploy!\n" unless @options[:json] || @options[:format] == 'json'
            return 0
          end
        end
      end
    end
  end
end
