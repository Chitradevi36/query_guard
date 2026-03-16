# frozen_string_literal: true

module QueryGuard
  # Main CLI entry point handling command routing and argument parsing
  class CLI
    def self.run(args)
      cli = new(args)
      cli.execute
    end

    def initialize(args)
      @args = args
      @command = nil
      @options = {}
      @path = '.'
    end

    def execute
      parse_arguments

      case @command
      when 'analyze'
        execute_analyze
      when 'check'
        execute_check
      when 'help', '--help', '-h', nil
        print_help
        exit 0
      when 'version', '--version', '-v'
        print_version
        exit 0
      else
        puts "Unknown command: #{@command}"
        print_help
        exit 1
      end
    end

    private

    # Parse command line arguments
    def parse_arguments
      @command = @args.shift&.downcase

      # Parse remaining arguments (options and path)
      while @args.any?
        arg = @args.shift

        case arg
        when '--help', '-h'
          @options[:help] = true
        when '--verbose', '-v'
          @options[:verbose] = true
        when '--json'
          @options[:json] = true
          @options[:format] = 'json'
        when '--format'
          format_value = @args.shift
          @options[:format] = format_value
          @options[:json] = true if format_value == 'json'
        when '--threshold'
          @options[:threshold] = @args.shift
        when '--config'
          @options[:config] = @args.shift
        when /^-/
          puts "Unknown option: #{arg}"
          exit 1
        else
          # Assume it's a path
          @path = arg
        end
      end
    end

    def execute_analyze
      if @options[:help]
        print_command_help('analyze')
        exit 0
      end

      command = Commands::Analyze.new(@path, @options)
      command.execute
    end

    def execute_check
      if @options[:help]
        print_command_help('check')
        exit 0
      end

      command = Commands::Check.new(@path, @options)
      exit_code = command.execute

      # Exit with appropriate code for check command
      exit exit_code
    end

    def print_help
      puts <<~HELP
        QueryGuard CLI v#{QueryGuard::VERSION}

        A developer-friendly tool for analyzing query risk and migration safety.

        USAGE:
          queryguard COMMAND [OPTIONS] [PATH]

        COMMANDS:
          analyze     Analyze a file or project for query and migration risks
          check       Check if risks are below configured threshold (for CI/CD)
          help        Show this help message
          version     Show version information

        OPTIONS:
          --help, -h           Show help for command
          --verbose, -v        Show detailed output
          --json              Output results as JSON
          --threshold LEVEL    Set severity threshold (info, warn, error, critical)
          --config FILE       Load configuration from file

        EXAMPLES:
          queryguard analyze                 # Analyze current directory
          queryguard analyze app/models      # Analyze specific directory
          queryguard check db/migrate        # Check migrations against threshold
          queryguard check --threshold error # Check with custom threshold

        For more information, visit: https://github.com/your-org/query_guard
      HELP
    end

    def print_command_help(command)
      case command
      when 'analyze'
        puts <<~HELP
          QueryGuard Analyze

          Analyzes files for query and migration risks, printing a report.

          USAGE:
            queryguard analyze [OPTIONS] [PATH]

          OPTIONS:
            --help, -h     Show this help message
            --verbose, -v  Show detailed information about each finding
            --json        Output results as JSON

          EXIT CODES:
            0  No errors (risks found may still exist)
            1  Analysis failed or invalid arguments

          EXAMPLES:
            queryguard analyze
            queryguard analyze --verbose
            queryguard analyze db/migrate
            queryguard analyze --json app/ > results.json
        HELP
      when 'check'
        puts <<~HELP
          QueryGuard Check

          Checks if migration/query risks exceed configured threshold.
          Useful for CI/CD pipelines.

          USAGE:
            queryguard check [OPTIONS] [PATH]

          OPTIONS:
            --help, -h           Show this help message
            --threshold LEVEL    Set severity threshold (default: warn)
                                 Levels: info, warn, error, critical
            --verbose, -v       Show detailed output
            --json              Output results as JSON

          EXIT CODES:
            0  No findings above threshold (clear to deploy)
            1  Findings exceed threshold (block deployment)
            2  Check failed or invalid arguments

          EXAMPLES:
            queryguard check db/migrate              # Check with default threshold
            queryguard check --threshold error       # Only fail on :error or :critical
            queryguard check --threshold critical    # Only fail on :critical
            queryguard check db/migrate --verbose    # Show all findings details
        HELP
      end
    end

    def print_version
      puts "QueryGuard v#{QueryGuard::VERSION}"
    end
  end
end

# Require command modules
require 'query_guard/cli/formatter'
require 'query_guard/cli/command'
require 'query_guard/cli/commands/analyze'
require 'query_guard/cli/commands/check'
