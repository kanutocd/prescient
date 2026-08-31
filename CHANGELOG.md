# Changelog

## Unreleased

### Added

- Added an optional, bounded Ruby agent runtime with strict single-action tool
  execution, provider routing through `Prescient::Client`, and safe loop limits.
- Added deterministic agent context compaction and safe serialization of tool
  failures before they are returned to the model.
- Added generic callable agent tools, request-scoped authorization and bounded
  telemetry hooks, the `prescient agent` CLI command, and `POST /v1/agent`.
- Added a dedicated `Prescient::Agent::CLIAdapter`, schema validation for
  generic callable tools, and independent task and response byte limits.
- Added structured failure telemetry, principal propagation, and an
  authenticated, bounded MCP Rack transport backed by shared JSON-RPC dispatch.
- Added valid UTF-8, JSON-safe observation truncation for bounded Agent context.
- Extended the MCP Rack transport with authenticated sessions, lifecycle
  termination, notifications, one-shot SSE responses, Origin checks, and a
  reusable bearer-token authentication policy.
- Documented the host-owned tenant/principal authorization contract and aligned
  the Agent implementation plan with the shipped REST and MCP surfaces.
- Added an opt-in thread-safe JSONL Agent audit sink for durable safe telemetry.
- Added an optional lazy MCP adapter with capability discovery, safe core
  operations, agent invocation, resources, and newline-delimited JSON-RPC stdio.

### Fixed

- Fixed Agent tool validation to enforce richer JSON Schema constraints,
  composition, and local references.
- Fixed request-scoped Agent authorization context handling for concurrent API
  requests and added regression coverage for principal isolation.
- Tightened generic callable Agent tools to require explicit object schemas
  instead of accepting unconstrained arguments.
- Added structured Agent failure telemetry for initialization failures and
  propagated telemetry configuration through CLI and REST Agent execution.

## [0.7.0] - 2025-08-17

### Added

- Added an explicit external-tool contract with a configurable SearXNG web-search adapter.
- Added YAML/schema configuration for tool registration, environment references, bounded requests, and normalized search results.
- Added `prescient search` and an annotated `web_search` configuration example.
- Added an optional development SearXNG service to `docker-compose.yml` for runnable web-search examples.
- Added opt-in search-to-provider context assembly through `Prescient.search_and_generate` and `prescient search --generate`.
- Added `POST /v1/search/generate` for REST API consumers to opt in to search-result context.
- Added `POST /v1/search` for normalized raw external-tool results without AI generation.
- Added SearchApi as a hosted web-search adapter with engine, location, language,
  country, API-key, timeout, and result-limit configuration.
- Added capability groups for ordered tool-adapter fallback on transient
  connection and rate-limit failures.
- Added bounded JSON document sources for Ruby, CLI, and REST generation context,
  including local files, in-memory documents, and injected Redis clients.
- Documented SearXNG and SearchApi setup and CLI usage side by side.
- Added explicit `--generate` opt-in behavior to the web-search example.
- Added `SEARXNG_URL` environment defaults for automatic `web_search` registration.
- Expanded `prescient config example` with documented SearXNG settings,
  environment references, custom tool names, and direct-versus-generated usage.
- Organized CLI help into global and search-specific option sections.

## [0.6.0] - 2025-08-15

### Added

- Added a dependency-free Rack-compatible REST API with generation, embeddings,
  bounded batch embeddings, provider/model discovery, capabilities, health,
  liveness, readiness, version, request IDs, authentication hooks, and JSON
  error envelopes.
- Added a small Rack example that lists the REST API endpoints and delegates
  requests to `Prescient::API`.
- Added an optional `rack_example` bundle group with Rack, Rackup, and Puma for
  running the example application without adding web-server dependencies to
  the library.
- Added a non-root, healthchecked Docker image and Compose example for the REST
  API, with optional GHCR publication on version tags.
- Documented mounting `Prescient::API` in Rails routes with its endpoint
  catalog and authentication example.
- Made the CLI and REST API optional lazy-loaded entry points so library users
  requiring only `prescient` do not load either interface eagerly.

## [0.5.0] - 2025-08-14

### Added

- Added a versioned YAML configuration loader with environment-variable references,
  configuration validation, precedence rules, and a packaged JSON Schema.
- Added YAML-configurable prompt templates and CLI prompt overrides, including
  support for loading multiline templates from a file.
- Added `prescient config example` for generating an annotated schema-backed YAML configuration starter.
- Added Google Gemini provider support for text generation, embeddings, health checks, and model listing.
- Added Gemini environment-variable defaults and YAML configuration support.
- Added Mistral provider support for text generation, embeddings, health checks, and model listing.
- Added Mistral environment-variable defaults and YAML configuration support.
- Added DeepSeek provider support for text generation, health checks, and model listing.
- Documented DeepSeek's unsupported embedding capability explicitly.
- Added xAI provider support for text generation, health checks, and model listing.
- Documented xAI's unsupported embedding capability explicitly.

### Changed

- Raised YARD documentation coverage enforcement from 99% to 100%.

## [0.4.0] - 2025-08-14

### Added

- Added the `prescient` CLI with provider listing, health checks, configuration validation, generation, embeddings, JSON output, stdin input, and exit-status handling.

### Changed

- Added CLI model overrides to provider generation and embedding operations.
- Added secure CLI credential sourcing with `--api-key-env`, alongside direct `--api-key` support for ephemeral automation.
- Documented all CLI automation overrides, including provider selection, generic and task-specific models, API keys, environment-backed credentials, and JSON output.

## [0.3.0] - 2025-08-14

### Added

- Added a development quality harness covering tests, RuboCop, YARD, and RBS tasks.
- Added 99% minimum line and branch coverage requirements with expanded provider and context coverage tests.
- Added an actionlint Rake task for GitHub Actions validation.
- Added Dependabot configuration for Bundler, Docker, and GitHub Actions updates.
- Added an opt-in `Prescient::Pgvector::Store` boundary for validated embedding storage and similarity search.
- Added configurable Ollama embedding dimensions while preserving strict validation when configured.
- Added a default example-syntax quality gate that validates Ruby examples without contacting providers.

### Changed

- Updated Ollama embeddings to use `/api/embed` with strict vector-dimension validation.
- Restricted fallback to transient/provider-service failures and added the public `ProviderError` exception for provider-side service errors.
- Reused registered provider instances and removed redundant health checks during fallback discovery.
- Updated default chat model names and README examples for current Ollama, Anthropic, OpenAI, and Hugging Face model selections.
- Updated Hugging Face inference to use the current router feature-extraction and OpenAI-compatible chat-completion APIs.
- Standardized provider reachability in health results and removed embedding padding/truncation across OpenAI and Hugging Face.
- Updated Anthropic model listing and health checks to use its `/v1/models` catalog endpoint.
- Retained OpenAI Chat Completions for the current normalized public response contract; Responses API migration remains a separately scoped compatibility change.
- Raised YARD API documentation coverage enforcement to 99% or higher and modernized gem development metadata.
- Compacted GitHub Actions into focused CI, Pages, release, and security workflows.
- Added credentialed, provider-selected live smoke tests that remain skipped by default.
- Restored the RBS/Steep development tasks with a committed Steepfile and curated core API signatures.
- Expanded Steep coverage to the base abstraction and all provider adapters, including their public operations and HTTP boundaries.
- Added configurable provider-info sensitive-key sanitization and configurable generic context-field exclusions.
- Audited README and documentation examples against the current codebase.
- Removed client `method_missing` delegation so provider-specific behavior is not exposed through the public client.
- Prevented default provider registration when required credentials are absent from the environment.
- Sanitized provider HTTP errors so raw response bodies are not exposed in exception messages.
- Removed fallback health probes before provider operations to avoid duplicate network requests and race conditions.
- Clarified health semantics: `reachable` reports transport availability and `ready` reports configured-model readiness.
- Added shared provider health-contract coverage for status, reachability, readiness, and provider identity.

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
