#!/usr/bin/env ruby

line = "add_column :users, :name, :string"

puts "Testing regex patterns on: #{line.inspect}"
puts "=" * 60

# Test the current pattern
if line.match?(/add_column\s+[:`]?(\w+)/)
  puts "CURRENT PATTERN MATCH: #{Regexp.last_match(1).inspect}"
else
  puts "CURRENT PATTERN NO MATCH"
end

# Test without char class - just colon
if line.match?(/add_column\s+:(\w+)/)
  puts "WITH COLON PATTERN: #{Regexp.last_match(1).inspect}"
else
  puts "WITH COLON PATTERN NO MATCH"
end

# Test without any colon
if line.match?(/add_column\s+(\w+)/)
  puts "NO COLON PATTERN: #{Regexp.last_match(1).inspect}"
else
  puts "NO COLON PATTERN NO MATCH"
end

# Test with optional colon
if line.match?(/add_column\s+:?(\w+)/)
  puts "OPTIONAL COLON PATTERN: #{Regexp.last_match(1).inspect}"
else
  puts "OPTIONAL COLON PATTERN NO MATCH"
end

# Test with quotes
if line.match?(/add_column\s+[":]?(\w+)/)
  puts "QUOTE/COLON PATTERN: #{Regexp.last_match(1).inspect}"
else
  puts "QUOTE/COLON PATTERN NO MATCH"
end

puts "=" * 60
puts "Testing on double-quoted variant:"
line2 = 'add_column "users", :name, :string'
puts "Input: #{line2.inspect}"

if line2.match?(/add_column\s+[":]?(\w+)/)
  puts "QUOTE/COLON PATTERN: #{Regexp.last_match(1).inspect}"
end

puts "=" * 60
puts "Testing what the current implementation in table_size_resolver does:"

# Simulate what table_size_resolver does
tables = Set.new
line = "add_column :users, :name, :string"
if line.include?("add_column") && line.match?(/add_column\s+[:`]?(\w+)/)
  matched = Regexp.last_match(1).to_s
  puts "Matched value: #{matched.inspect}"
  tables << matched
end
puts "Tables set: #{tables.inspect}"
puts "As array: #{tables.to_a.inspect}"
