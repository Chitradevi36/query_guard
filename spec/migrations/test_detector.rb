#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../lib/query_guard/migrations/migration_risk_detectors'

migration_file = File.expand_path(File.join(__dir__, "fixture_migrations/20240101000001_create_users_table.rb"))
content = File.read(migration_file)

puts "=== Testing Migration Risk Detection ==="
puts "File: #{migration_file}"
puts ""
puts "=== File Content ==="
puts content
puts ""

# Test pattern directly
puts "=== Testing Regex Patterns ==="
puts "Looking for 'add_index' calls..."
add_index_count = 0
content.scan(/add_index\s*\(/m) do
  add_index_count += 1
  start_pos = Regexp.last_match.offset(0)[0]
  line_num = content[0...start_pos].count("\n") + 1
  lookahead = content[start_pos...start_pos + 300]
  puts "  Found at line #{line_num}"
  puts "    Lookahead: #{lookahead[0..50]}"
  puts "    Has 'algorithm: :concurrently'? #{lookahead.include?("algorithm: :concurrently")}"
end
puts "Total add_index matches: #{add_index_count}"
puts ""

puts "=== Detecting Risks ==="
risks = QueryGuard::Migrations::MigrationRiskDetectors.detect_risks(content, "test_migration")
puts "Found #{risks.length} risks:"
risks.each do |risk|
  puts "  - #{risk[:type]} at line #{risk[:line_number]}: #{risk[:message]}"
end

