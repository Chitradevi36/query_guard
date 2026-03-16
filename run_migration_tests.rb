#!/usr/bin/env ruby
# frozen_string_literal: true

require 'rspec'

# Add lib to load path
$LOAD_PATH.unshift File.expand_path('lib', __dir__)

# Require all necessary files
require 'query_guard'
require 'query_guard/migrations/migration_risk_detectors'
require 'query_guard/migrations/migration_analyzer'

# Run the specifications
rspec_args = [
  'spec/migrations/migration_analyzer_spec.rb',
  '--color',
  '--format', 'progress'
]

RSpec::Core::Runner.run(rspec_args)
