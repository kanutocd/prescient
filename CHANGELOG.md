# Changelog

## Unreleased

### Added

- Added a development quality harness covering tests, RuboCop, YARD, and RBS tasks.
- Added 99% minimum line and branch coverage requirements with expanded provider and context coverage tests.
- Added an actionlint Rake task for GitHub Actions validation.
- Added Dependabot configuration for Bundler, Docker, and GitHub Actions updates.

### Changed

- Updated Ollama embeddings to use `/api/embed` with strict vector-dimension validation.
- Restricted fallback to transient/provider-service failures and added the public `ProviderError` exception for provider-side service errors.
- Reused registered provider instances and removed redundant health checks during fallback discovery.
- Updated default chat model names and README examples for current Ollama, Anthropic, OpenAI, and Hugging Face model selections.
- Updated Hugging Face inference to use the current router feature-extraction and OpenAI-compatible chat-completion APIs.
- Added credentialed, provider-selected live smoke tests that remain skipped by default.
- Restored the RBS/Steep development tasks with a committed Steepfile and curated core API signatures.

### Removed

- Removed the nonfunctional Steep/RBS check from the development quality harness.
- Raised YARD API documentation coverage enforcement to 99% or higher.
- Modernized gem development dependencies, packaging metadata, YARD configuration, and Ruby CI support.
- Compacted GitHub Actions into focused CI, Pages, release, and security workflows.

### Removed

- Removed the obsolete PDF changelog and superseded workflow definitions.

## [0.2.0] - 2025-08-05

### Added

- Added new featire: Providers fallbacks mechanism

## [0.1.0] - 2025-08-05

### Added

- Initial release of Prescient gem
- Support for four AI providers:
  - **Ollama**: Local AI provider with embedding and text generation
  - **Anthropic**: Claude models for text generation
  - **OpenAI**: GPT models and embeddings
  - **HuggingFace**: Open-source models and embeddings
- Unified client interface for all providers
- Comprehensive error handling with provider-specific exceptions:
  - `ConnectionError` for network issues
  - `AuthenticationError` for API key problems
  - `RateLimitError` for rate limiting
  - `ModelNotAvailableError` for missing models
  - `InvalidResponseError` for malformed responses
- Automatic retry logic with configurable attempts and delays
- Health monitoring capabilities for all providers
- Environment variable configuration support
- Programmatic configuration system
- Context-aware generation support with context items
- Text preprocessing and embedding normalization
- Provider availability checking
- Model listing capabilities (where supported)
- Comprehensive test suite with RSpec
- Documentation and usage examples

### Provider-Specific Features

- **Ollama**: Model management (pull, list), local deployment
- **Anthropic**: Latest Claude 3 models (Haiku, Sonnet, Opus)
- **OpenAI**: Multiple embedding dimensions, latest GPT models
- **HuggingFace**: Open-source model support, research-friendly API

### Development

- RSpec test suite with WebMock and VCR
- RuboCop code style enforcement
- SimpleCov test coverage reporting
- Comprehensive documentation
- Example usage scripts
- Rake tasks for testing and linting

## [0.0.0] - 2025-08-05

### Added

- Project initialization
- Basic gem structure
- Core interfaces defined
