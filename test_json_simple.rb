#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', Dir.pwd)

require 'json'
require 'query_guard/cli/formatter'

findings = [
  {
    title: 'Test',
    analyzer_name: :test,
    rule_name: :rule,
    severity: :warn,
    file_path: 'test.rb',
    line_number: 1,
    description: 'Test',
    recommendation: 'Fix',
    metadata: {}
  }
]

puts "Testing JSON formatter..."
formatter = QueryGuard::CLI::Formatter.new(json: true)
formatter.print_findings(findings, 'Test')
puts "\nDone!"
