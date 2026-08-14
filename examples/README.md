# Prescient examples

These scripts demonstrate the supported public API. They use the local
library checkout, so run them from the repository root after installing the
development dependencies:

```bash
bundle install
```

## Examples

- `basic_usage.rb` — default-provider generation, embeddings, health checks,
  provider selection, and custom configuration.
- `custom_prompts.rb` — system prompts and no-context/with-context templates.
- `custom_contexts.rb` — explicit context types, field matching, formatting,
  and embedding field selection.
- `vector_search.rb` — `Prescient::Pgvector::Store` PostgreSQL/pgvector storage
  and similarity search.
- `rest_api.ru` — a tiny Rack-compatible application that mounts
  `Prescient::API` and lists its endpoints at `/`.

Run the REST API example with a Rack server such as `rackup`:

```bash
BUNDLE_WITH=rack_example bundle install
PRESCIENT_API_TOKEN=change-me BUNDLE_WITH=rack_example \
  bundle exec rackup -s puma examples/rest_api.ru
curl http://localhost:9292/
```

Running `bundle exec ruby examples/rest_api.ru` directly prints the same
endpoint catalog without starting a server.

The example does not add Rack as a Prescient runtime dependency; it only uses
the Rack-compatible `call` interface provided by `Prescient::API`.

The first three examples use Ollama by default. Start Ollama and pull the
current local models before running them:

```bash
docker compose up -d ollama
docker compose run --rm ollama-init
bundle exec ruby examples/basic_usage.rb
```

The vector-search example additionally requires PostgreSQL with pgvector:

```bash
docker compose up -d postgres ollama
docker compose run --rm ollama-init
DB_HOST=localhost bundle exec ruby examples/vector_search.rb
```

Cloud-provider examples require the corresponding credentials and provider
configuration. The scripts are demonstrations rather than isolated test
fixtures; they may make real provider requests when the configured service is
available.

See the [main README](../README.md) for configuration, fallback behavior,
prompt templates, context exclusions, embeddings, and the public API. Rails
applications can also use the [integration guide](../INTEGRATION_GUIDE.md),
and PostgreSQL users should read the [pgvector guide](../VECTOR_SEARCH_GUIDE.md).
