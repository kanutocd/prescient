# Contributing to Prescient

Thank you for your interest in contributing to Prescient! Prescient is a Ruby gem that provides a unified, predictable gateway to multiple AI providers, including Ollama, OpenAI, Anthropic, Google Gemini, Mistral, Hugging Face, DeepSeek, and xAI.

Prescient is designed as a reusable library rather than an application. The library values explicit provider boundaries, predictable error handling, modern idiomatic Ruby, and stable public APIs.

This guide explains how to set up your local development environment, run tests, follow coding standards, and submit pull requests.

---

## Code of conduct

By participating in this project, you agree to follow the project's [Code of Conduct](CODE_OF_CONDUCT.md).

---

## Development setup

### Prerequisites

Ensure you have the following installed on your local system:

- **Ruby**: Version 3.2 or higher (the CI matrix tests Ruby 3.2, 3.3, 3.4, and 4.0).
- **Bundler**: Version 2.0 or higher.
- **Docker & Docker Compose** *(optional, for local service testing)*: Required if you test against local instances of Ollama, SearXNG, or PostgreSQL with pgvector.

### Setting up the workspace

1. Fork and clone the repository:

   ```bash
   git clone https://github.com/kanutocd/prescient.git
   cd prescient
   ```

2. Install development dependencies:

   ```bash
   bundle install
   ```

3. *(Optional)* Start local services using Docker Compose:

   ```bash
   docker compose up -d ollama postgres searxng
   docker compose run --rm ollama-init
   ```

---

## Running tests and checks

Prescient uses Minitest for unit and integration testing, RuboCop for code linting, and RBS/Steep for type checking. Establish a green test baseline before making changes.

### Running unit and integration tests

Run the complete test suite:

```bash
bundle exec rake test
```

To run a single test file during development, execute:

```bash
bundle exec ruby -Itest test/prescient/client_test.rb
```

To run a specific test by name, pass the line or name filter:

```bash
bundle exec ruby -Itest test/prescient/client_test.rb -n /generate_response/
```

### Running code linter

Prescient enforces RuboCop styling rules:

```bash
bundle exec rubocop
```

Fix safe auto-correctable offenses with:

```bash
bundle exec rubocop -A
```

### Type validation with RBS and Steep

Validate core API type signatures with:

```bash
bundle exec rake rbs:validate
```

To inspect generated RBS prototypes or differences:

```bash
bundle exec rake rbs:prototype
bundle exec rake rbs:diff
```

### Opt-in live provider smoke tests

The default test suite uses WebMock and VCR to mock external HTTP requests. Tests never execute against live cloud providers by default.

To test against live provider APIs, set `PRESCIENT_LIVE_SMOKE=1` and specify the target providers in `PRESCIENT_LIVE_PROVIDERS`:

```bash
PRESCIENT_LIVE_SMOKE=1 \
PRESCIENT_LIVE_PROVIDERS=openai \
OPENAI_API_KEY=your_actual_key \
bundle exec ruby -Itest test/prescient/live_provider_smoke_test.rb
```

Supported live provider keys are `ollama`, `openai`, `anthropic`, `gemini`, `mistral`, `huggingface`, `deepseek`, and `xai`.

---

## Architecture guidelines

### Provider abstraction

Provider-specific behavior belongs in provider adapters (`lib/prescient/provider/`). Common behavior belongs in base abstractions (`lib/prescient/base.rb`).

When creating or updating a provider adapter:

1. **Inherit from `Prescient::Base`**: Subclass `Prescient::Base` and define required methods: `#generate_response`, `#generate_embedding` (if supported), and `#health_check`.
2. **Isolate HTTP details**: Use HTTParty or standard-library HTTP tools inside the adapter. Keep raw network details out of caller code.
3. **Normalize Responses**: Return standard response shapes from `#generate_response`:
   ```ruby
   {
     response: "Generated text response",
     model: "configured-model-name",
     provider: "provider_name",
     processing_time: nil,
     metadata: { ... }
   }
   ```
4. **Enforce embedding dimensions**: Validate vectors with `validate_embedding_dimensions`. Never pad or truncate vectors silently.
5. **Map Provider Errors**: Wrap raw HTTP or API errors into standard Prescient exception classes.

### Error mapping hierarchy

All gem exceptions inherit from `Prescient::Error`. Map provider-specific failures into the appropriate exception category:

| Exception Class | Primary Cause | Retryable by Fallback? |
| :--- | :--- | :--- |
| `Prescient::ConnectionError` | Network failures, HTTP timeouts, DNS resolution failures | Yes |
| `Prescient::RateLimitError` | Provider HTTP 429 status | Yes |
| `Prescient::ModelNotAvailableError` | Provider HTTP 404 status or unavailable model | Yes |
| `Prescient::ProviderError` | Provider HTTP 5xx server errors | Yes |
| `Prescient::AuthenticationError` | Provider HTTP 401/403 invalid API keys | No |
| `Prescient::InvalidResponseError` | Malformed JSON responses or vector dimension mismatches | No |
| `Prescient::ToolError` | Base class for external search tool adapter failures | Varies |

### Retry vs fallback semantics

- **Retries**: Retries apply to transient network errors (`ConnectionError`, `RateLimitError`) within a single provider, governed by `config.retry_attempts` and `config.retry_delay`.
- **Fallback**: Provider fallback triggers when a provider encounters a persistent or service-side failure (`ConnectionError`, `RateLimitError`, `ModelNotAvailableError`, `ProviderError`). Fallback cascades in configured provider order. Caller misuse (invalid parameters, authentication failures) is never retried with fallback.

---

## Public API compatibility

Treat the following items as public API contracts:

- Methods on `Prescient`: `.configure`, `.client`, `.generate_embedding`, `.generate_response`, `.search_and_generate`, `.health_check`, `.load_configuration`.
- Configuration options: `Configuration` class properties (`default_provider`, `timeout`, `retry_attempts`, `retry_delay`, `fallback_providers`, `sensitive_keys`).
- Standard return shapes for generation, embeddings, health checks, and tool search results.

If your changes modify a public API contract:

1. Update the corresponding unit and integration tests in `test/`.
2. Update example scripts in `examples/`.
3. Update documentation files (`README.md`, `INTEGRATION_GUIDE.md`, `VECTOR_SEARCH_GUIDE.md`).

---

## Submitting pull requests

Before opening a pull request:

1. Ensure all tests pass: `bundle exec rake test`.
2. Ensure RuboCop checks pass: `bundle exec rubocop`.
3. Inspect your diff to ensure no sensitive credentials, VCR tokens, or temporary files are included:
   ```bash
   git diff
   ```
4. Write clear, imperative commit messages (for example, `Add Google Gemini model listing support`).
5. Open a pull request against the `main` branch with a clear description of your changes and motivation.
