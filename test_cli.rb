#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple CLI tests focused on command behavior
require 'tempfile'
require 'fileutils'

$LOAD_PATH.unshift File.expand_path('lib', __dir__)

require 'query_guard/version'
require 'query_guard/cli/formatter'
require 'query_guard/cli/command'
require 'query_guard/cli/commands/analyze'
require 'query_guard/cli/commands/check'

class SimpleTestRunner
  def initialize
    @tests = 0
    @passed = 0
    @failed = 0
    @failures = []
  end

  def test(description)
    @tests += 1
    begin
      yield
      @passed += 1
      puts "  ✓ #{description}"
    rescue => e
      @failed += 1
      puts "  ✗ #{description}: #{e.message}"
      @failures << "#{description}: #{e.message}"
    end
  end

  def assert_equal(actual, expected, message = "")
    unless actual == expected
      raise "Expected #{expected.inspect}, got #{actual.inspect}. #{message}"
    end
  end

  def assert_true(value, message = "")
    unless value
      raise "Expected true, got #{value.inspect}. #{message}"
    end
  end

  def assert_false(value, message = "")
    if value
      raise "Expected false, got #{value.inspect}. #{message}"
    end
  end

  def summary
    puts ""
    puts "=" * 60
    puts "Test Summary: #{@passed}/#{@tests} passed"
    puts "=" * 60

    if @failed > 0
      puts "\nFailures:"
      @failures.each { |f| puts "  • #{f}" }
      return false
    end
    true
  end
end

runner = SimpleTestRunner.new

puts "Running CLI Component Tests"
puts "=" * 60

puts "\nFormatter Tests"

runner.test("Formatter format_row_count handles small numbers") do
  formatter = QueryGuard::CLI::Formatter.new(json: false)
  result = formatter.send(:format_row_count, 500)
  runner.assert_equal(result, "500")
end

runner.test("Formatter format_row_count formats thousands") do
  formatter = QueryGuard::CLI::Formatter.new(json: false)
  result = formatter.send(:format_row_count, 50_000)
  runner.assert_equal(result, "50.0K")
end

runner.test("Formatter format_row_count formats millions") do
  formatter = QueryGuard::CLI::Formatter.new(json: false)
  result = formatter.send(:format_row_count, 5_000_000)
  runner.assert_equal(result, "5.0M")
end

runner.test("Formatter format_row_count formats billions") do
  formatter = QueryGuard::CLI::Formatter.new(json: false)
  result = formatter.send(:format_row_count, 50_000_000_000)
  runner.assert_equal(result, "50.0B")
end

runner.test("Formatter severity_icon returns correct emoji") do
  formatter = QueryGuard::CLI::Formatter.new(json: false)
  runner.assert_equal(formatter.send(:severity_icon, :critical), "🚨")
  runner.assert_equal(formatter.send(:severity_icon, :error), "❌")
  runner.assert_equal(formatter.send(:severity_icon, :warn), "⚠️ ")
  runner.assert_equal(formatter.send(:severity_icon, :info), "ℹ️ ")
end

puts "\nCommand Base Class Tests"

test_dir = Dir.mktmpdir('cli_test')
at_exit { FileUtils.rm_rf(test_dir) }

runner.test("Command severity_to_number maps correctly") do
  cmd = QueryGuard::CLI::Command.new(test_dir)
  runner.assert_equal(cmd.send(:severity_to_number, :critical), 4)
  runner.assert_equal(cmd.send(:severity_to_number, :error), 3)
  runner.assert_equal(cmd.send(:severity_to_number, :warn), 2)
  runner.assert_equal(cmd.send(:severity_to_number, :info), 1)
end

runner.test("Command threshold_to_number defaults to warn") do
  cmd = QueryGuard::CLI::Command.new(test_dir)
  runner.assert_equal(cmd.send(:threshold_to_number, nil), 2)
  runner.assert_equal(cmd.send(:threshold_to_number, ''), 2)
end

runner.test("Command threshold_to_number parses critical") do
  cmd = QueryGuard::CLI::Command.new(test_dir)
  runner.assert_equal(cmd.send(:threshold_to_number, 'critical'), 4)
  runner.assert_equal(cmd.send(:threshold_to_number, 'CRITICAL'), 4)
end

runner.test("Command threshold_to_number parses error") do
  cmd = QueryGuard::CLI::Command.new(test_dir)
  runner.assert_equal(cmd.send(:threshold_to_number, 'error'), 3)
  runner.assert_equal(cmd.send(:threshold_to_number, 'ERROR'), 3)
end

runner.test("Command threshold_to_number parses warn") do
  cmd = QueryGuard::CLI::Command.new(test_dir)
  runner.assert_equal(cmd.send(:threshold_to_number, 'warn'), 2)
  runner.assert_equal(cmd.send(:threshold_to_number, 'WARN'), 2)
end

runner.test("Command threshold_to_number parses info") do
  cmd = QueryGuard::CLI::Command.new(test_dir)
  runner.assert_equal(cmd.send(:threshold_to_number, 'info'), 1)
  runner.assert_equal(cmd.send(:threshold_to_number, 'INFO'), 1)
end

puts "\nCheck Command Tests"

runner.test("Check command detects findings exceed threshold - error > warn") do
  cmd = QueryGuard::CLI::Commands::Check.new(test_dir, { threshold: 'warn' })
  findings = [
    { severity: :error, title: "Test", type: :test, line_number: 1 }
  ]
  exceeds = cmd.send(:findings_exceed_threshold?, findings, 'warn')
  runner.assert_true(exceeds)
end

runner.test("Check command detects findings exceed threshold - critical > error") do
  cmd = QueryGuard::CLI::Commands::Check.new(test_dir, { threshold: 'error' })
  findings = [
    { severity: :critical, title: "Test", type: :test, line_number: 1 }
  ]
  exceeds = cmd.send(:findings_exceed_threshold?, findings, 'error')
  runner.assert_true(exceeds)
end

runner.test("Check command detects findings do not exceed threshold - info < warn") do
  cmd = QueryGuard::CLI::Commands::Check.new(test_dir, { threshold: 'warn' })
  findings = [
    { severity: :info, title: "Test", type: :test, line_number: 1 }
  ]
  exceeds = cmd.send(:findings_exceed_threshold?, findings, 'warn')
  runner.assert_false(exceeds)
end

runner.test("Check command detects findings at threshold level - exact match") do
  cmd = QueryGuard::CLI::Commands::Check.new(test_dir, { threshold: 'error' })
  findings = [
    { severity: :error, title: "Test", type: :test, line_number: 1 }
  ]
  exceeds = cmd.send(:findings_exceed_threshold?, findings, 'error')
  runner.assert_true(exceeds)
end

runner.test("Check command detects mixed findings above threshold") do
  cmd = QueryGuard::CLI::Commands::Check.new(test_dir, { threshold: 'error' })
  findings = [
    { severity: :info, title: "Info", type: :test, line_number: 1 },
    { severity: :warn, title: "Warning", type: :test, line_number: 2 },
    { severity: :critical, title: "Critical!", type: :test, line_number: 3 }
  ]
  exceeds = cmd.send(:findings_exceed_threshold?, findings, 'error')
  runner.assert_true(exceeds)
end

runner.test("Check command detects mixed findings below threshold") do
  cmd = QueryGuard::CLI::Commands::Check.new(test_dir, { threshold: 'critical' })
  findings = [
    { severity: :info, title: "Info", type: :test, line_number: 1 },
    { severity: :warn, title: "Warning", type: :test, line_number: 2 },
    { severity: :error, title: "Error", type: :test, line_number: 3 }
  ]
  exceeds = cmd.send(:findings_exceed_threshold?, findings, 'critical')
  runner.assert_false(exceeds)
end

puts "\nAnalyze Command Tests"

runner.test("Analyze command path_exists validates directory") do
  cmd = QueryGuard::CLI::Commands::Analyze.new(test_dir)
  runner.assert_true(cmd.send(:path_exists?))
end

runner.test("Analyze command path_exists returns false for nonexistent") do
  cmd = QueryGuard::CLI::Commands::Analyze.new('/nonexistent/path/xyz')
  runner.assert_false(cmd.send(:path_exists?))
end

runner.test("Analyze command path_absolute returns full path") do
  cmd = QueryGuard::CLI::Commands::Analyze.new('.')
  path = cmd.send(:path_absolute)
  runner.assert_true(File.exist?(path))
end

puts "\nOutput Formatting Tests"

runner.test("Formatter option verbose controls detail level") do
  formatter_verbose = QueryGuard::CLI::Formatter.new(verbose: true)
  formatter_quiet = QueryGuard::CLI::Formatter.new(verbose: false)

  runner.assert_true(formatter_verbose.instance_variable_get(:@verbose))
  runner.assert_false(formatter_quiet.instance_variable_get(:@verbose))
end

runner.test("Formatter option json toggles JSON output") do
  formatter_text = QueryGuard::CLI::Formatter.new(json: false)
  formatter_json = QueryGuard::CLI::Formatter.new(json: true)

  runner.assert_false(formatter_text.instance_variable_get(:@json))
  runner.assert_true(formatter_json.instance_variable_get(:@json))
end

puts "\nCLI Main Entry Point Tests"

runner.test("CLI parses analyze command") do
  require 'query_guard/cli'
  cli = QueryGuard::CLI.new(['analyze'])
  cli.send(:parse_arguments)
  runner.assert_equal(cli.instance_variable_get(:@command), 'analyze')
end

runner.test("CLI parses check command") do
  require 'query_guard/cli'
  cli = QueryGuard::CLI.new(['check'])
  cli.send(:parse_arguments)
  runner.assert_equal(cli.instance_variable_get(:@command), 'check')
end

runner.test("CLI parses path argument") do
  require 'query_guard/cli'
  cli = QueryGuard::CLI.new(['analyze', '/tmp/test'])
  cli.send(:parse_arguments)
  runner.assert_equal(cli.instance_variable_get(:@path), '/tmp/test')
end

runner.test("CLI parses verbose flag") do
  require 'query_guard/cli'
  cli = QueryGuard::CLI.new(['analyze', '--verbose'])
  cli.send(:parse_arguments)
  options = cli.instance_variable_get(:@options)
  runner.assert_true(options[:verbose])
end

runner.test("CLI parses json flag") do
  require 'query_guard/cli'
  cli = QueryGuard::CLI.new(['analyze', '--json'])
  cli.send(:parse_arguments)
  options = cli.instance_variable_get(:@options)
  runner.assert_true(options[:json])
end

runner.test("CLI parses threshold option") do
  require 'query_guard/cli'
  cli = QueryGuard::CLI.new(['check', '--threshold', 'error'])
  cli.send(:parse_arguments)
  options = cli.instance_variable_get(:@options)
  runner.assert_equal(options[:threshold], 'error')
end

runner.test("CLI defaults path to current directory") do
  require 'query_guard/cli'
  cli = QueryGuard::CLI.new(['analyze'])
  cli.send(:parse_arguments)
  runner.assert_equal(cli.instance_variable_get(:@path), '.')
end

runner.test("CLI lowercase-ifies command") do
  require 'query_guard/cli'
  cli = QueryGuard::CLI.new(['ANALYZE'])
  cli.send(:parse_arguments)
  runner.assert_equal(cli.instance_variable_get(:@command), 'analyze')
end

runner.summary
exit(runner.summary ? 0 : 1)
