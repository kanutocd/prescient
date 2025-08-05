# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2024-01-XX

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
