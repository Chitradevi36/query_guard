#!/usr/bin/env ruby
# frozen_string_literal: true

# Load the detector code
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'query_guard/migrations/migration_risk_detectors'

# Test with fixture migration
fixture_path = File.join(__dir__, 'spec/migrations/fixture_migrations/20240101000001_create_users_table.rb')
content = File.read(fixture_path)

puts "=== Testing Migration Risk Detection (Simplified) ==="
puts "File: #{fixture_path}"
puts ""
puts "=== File Content ==="
puts content
puts ""
puts "=== Detecting Risks ==="

risks = QueryGuard::Migrations::MigrationRiskDetectors.detect_risks(content, '20240101000001_create_users_table')

puts "Found #{risks.length} risks:"
risks.each do |risk|
  puts "  Line #{risk[:line_number]}: #{risk[:type]} (#{risk[:severity]}) - #{risk[:title]}"
  puts "    Message: #{risk[:message]}"
end

puts ""
puts "Testing other migrations..."

# Test non-null without default
fixture2 = File.join(__dir__, 'spec/migrations/fixture_migrations/20240102000001_add_status_to_users.rb')
puts "\nFile: #{File.basename(fixture2)}"
risks2 = QueryGuard::Migrations::MigrationRiskDetectors.detect_risks(File.read(fixture2), '20240102000001_add_status_to_users')
puts "Found #{risks2.length} risks"
risks2.each { |r| puts "  - #{r[:type]} on line #{r[:line_number]}" }

# Test change column
fixture3 = File.join(__dir__, 'spec/migrations/fixture_migrations/20240103000001_change_email_type_on_users.rb')
puts "\nFile: #{File.basename(fixture3)}"
risks3 = QueryGuard::Migrations::MigrationRiskDetectors.detect_risks(File.read(fixture3), '20240103000001_change_email_type_on_users')
puts "Found #{risks3.length} risks"
risks3.each { |r| puts "  - #{r[:type]} on line #{r[:line_number]}" }

# Test update_all
fixture4a = File.join(__dir__, 'spec/migrations/fixture_migrations/20240104000001_populate_status_on_users.rb')
puts "\nFile: #{File.basename(fixture4a)}"
risks4a = QueryGuard::Migrations::MigrationRiskDetectors.detect_risks(File.read(fixture4a), '20240104000001_populate_status_on_users')
puts "Found #{risks4a.length} risks"
risks4a.each { |r| puts "  - #{r[:type]} on line #{r[:line_number]}" }

# Test dangerous SQL
fixture4b = File.join(__dir__, 'spec/migrations/fixture_migrations/20240105000001_migrate_old_data.rb')
puts "\nFile: #{File.basename(fixture4b)}"
risks4b = QueryGuard::Migrations::MigrationRiskDetectors.detect_risks(File.read(fixture4b), '20240105000001_migrate_old_data')
puts "Found #{risks4b.length} risks"
risks4b.each { |r| puts "  - #{r[:type]} on line #{r[:line_number]}" }

# Test remove/rename columns
fixture5 = File.join(__dir__, 'spec/migrations/fixture_migrations/20240106000001_remove_and_rename_columns.rb')
puts "\nFile: #{File.basename(fixture5)}"
risks5 = QueryGuard::Migrations::MigrationRiskDetectors.detect_risks(File.read(fixture5), '20240106000001_remove_and_rename_columns')
puts "Found #{risks5.length} risks"
risks5.each { |r| puts "  - #{r[:type]} on line #{r[:line_number]}" }

# Test safe migrations
fixture6 = File.join(__dir__, 'spec/migrations/fixture_migrations/20240107000001_add_index_concurrently_to_users.rb')
puts "\nFile: #{File.basename(fixture6)}"
risks6 = QueryGuard::Migrations::MigrationRiskDetectors.detect_risks(File.read(fixture6), '20240107000001_add_index_concurrently_to_users')
puts "Found #{risks6.length} risks (should be 0)"

fixture7 = File.join(__dir__, 'spec/migrations/fixture_migrations/20240108000001_add_default_status_to_users.rb')
puts "\nFile: #{File.basename(fixture7)}"
risks7 = QueryGuard::Migrations::MigrationRiskDetectors.detect_risks(File.read(fixture7), '20240108000001_add_default_status_to_users')
puts "Found #{risks7.length} risks (should be 0)"
