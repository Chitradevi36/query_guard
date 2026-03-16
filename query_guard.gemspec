# frozen_string_literal: true

require_relative "lib/query_guard/version"

Gem::Specification.new do |spec|
  spec.name = "query_guard"
  spec.version = QueryGuard::VERSION
  spec.authors = ["Chitradevi36"]
  spec.email = ["chitra.rajaguru123@gmail.com"]

  spec.summary = "Database migration safety analyzer for Rails"
  spec.description = "Automatically detect risky migration patterns (unsafe column removal, locking operations, data loss) before they reach production."
  spec.homepage = "https://github.com/Chitradevi36/query_guard"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] =  spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.add_development_dependency "rake", "~> 13.2"
  spec.add_dependency "activesupport", ">= 5.2", "< 8.0"
  spec.add_dependency "rails", ">= 5.2", "< 8.0"  


  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob("lib/**/*") + Dir.glob("exe/**/*") + Dir.glob("sig/**/*") + %w[
    README.md
    LICENSE.txt
    CHANGELOG.md
    INDEX.md
    DESIGN.md
  ]
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
