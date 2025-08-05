# frozen_string_literal: true

require_relative "lib/prescient/version"

Gem::Specification.new do |spec|
  spec.name = "prescient"
  spec.version = Prescient::VERSION
  spec.authors = ["Ken C. Demanawa"]
  spec.email = ["kenneth.c.demanawa@gmail.com"]

  spec.summary = "Prescient AI provider abstraction for Ruby applications"
  spec.description = "Prescient provides a unified interface for AI providers including local Ollama, Anthropic Claude, OpenAI GPT, and HuggingFace models. Built for AI applications with error handling, health monitoring, and provider switching."
  spec.homepage = "https://github.com/yourcompany/prescient"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/yourcompany/prescient"
  spec.metadata["changelog_uri"] = "https://github.com/yourcompany/prescient/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "httparty", "~> 0.22.0"
  
  # Optional dependencies for vector database integration
  spec.add_development_dependency "pg", "~> 1.5" # PostgreSQL adapter for pgvector integration

  # Development dependencies
  spec.add_development_dependency "minitest", "~> 5.20"
  spec.add_development_dependency "mocha", "~> 2.1"
  spec.add_development_dependency "webmock", "~> 3.18"
  spec.add_development_dependency "vcr", "~> 6.1"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "rubocop-minitest", "~> 0.35"
  spec.add_development_dependency "rubocop-performance", "~> 1.19"
  spec.add_development_dependency "rubocop-rake", "~> 0.6"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "irb"
end
