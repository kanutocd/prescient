# frozen_string_literal: true

require_relative "lib/prescient/version"

Gem::Specification.new do |spec|
  spec.name = "prescient"
  spec.version = Prescient::VERSION
  spec.authors = ["Ken C. Demanawa"]
  spec.email = ["kenneth.c.demanawa@gmail.com"]

  spec.summary = "A boring AI provider gateway for Ruby"
  spec.description =<<~DESC
    Prescient provides a consistent Ruby API, CLI, or REST API for AI providers including
    Ollama, OpenAI, Anthropic, Hugging Face, Google Gemini, Mistral, DeepSeek, and xAI,
    with provider selection, retries, health checks, and fallback across configured providers.
  DESC

  spec.homepage = "https://kanutocd.github.io/prescient"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/kanutocd/prescient"
  spec.metadata["changelog_uri"] = "https://github.com/kanutocd/prescient/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    files = if File.directory?(File.join(__dir__, ".git"))
              `git ls-files -z`.split("\x0")
            else
              Dir.glob("**/*", File::FNM_DOTMATCH).select { |file| File.file?(file) }
            end

    files.reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "httparty", ">= 0.24.0"
end
