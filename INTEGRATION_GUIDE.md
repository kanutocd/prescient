# AI Providers Integration Guide

This guide explains how to integrate the Prescient gem into an existing Rails AI application.

For the canonical public API and runnable scripts, see the [README](README.md)
and [examples guide](examples/README.md).

## Integration Steps

### 1. Update Your Gemfile

```ruby
# Add to your Gemfile
gem 'prescient', '~> 0.7.0'
```

### 2. Replace Existing AI Service

**Before (Original OllamaService):**

```ruby
# app/services/ollama_service.rb
class OllamaService
  def generate_embedding(text)
    # Direct Ollama API calls
  end

  def generate_response(prompt, context_items)
    # Direct Ollama API calls
  end
end
```

**After (Using Prescient):**

```ruby
# app/services/ai_service.rb
class AIService
  def self.client(provider = nil)
    @clients ||= {}
    provider_name = provider || Rails.application.config.default_ai_provider
    @clients[provider_name] ||= Prescient.client(provider_name)
  end

  def self.generate_embedding(text, provider: nil)
    client(provider).generate_embedding(text)
  rescue Prescient::Error => e
    Rails.logger.error "AI embedding generation failed: #{e.message}"
    raise
  end

  def self.generate_response(prompt, context_items = [], provider: nil, **options)
    client(provider).generate_response(prompt, context_items, **options)
  rescue Prescient::Error => e
    Rails.logger.error "AI response generation failed: #{e.message}"
    raise
  end

  def self.health_check(provider: nil)
    client(provider).health_check
  rescue Prescient::Error => e
    { status: 'unhealthy', error: e.message }
  end
end
```

### 3. Configuration

**Create initializer:**

```ruby
# config/initializers/prescient.rb
Prescient.configure do |config|
  config.default_provider = Rails.env.production? ? :openai : :ollama
  config.timeout = 60
  config.retry_attempts = 3
  config.retry_delay = 1.0

  # Ollama (Local/Development)
  config.add_provider(:ollama, Prescient::Provider::Ollama,
    url: ENV.fetch('OLLAMA_URL', 'http://localhost:11434'),
    embedding_model: ENV.fetch('OLLAMA_EMBEDDING_MODEL', 'nomic-embed-text'),
    chat_model: ENV.fetch('OLLAMA_CHAT_MODEL', 'llama3.2:3b'),
    timeout: 120
  )

  # OpenAI (Production)
  if ENV['OPENAI_API_KEY'].present?
    config.add_provider(:openai, Prescient::Provider::OpenAI,
      api_key: ENV['OPENAI_API_KEY'],
      embedding_model: ENV.fetch('OPENAI_EMBEDDING_MODEL', 'text-embedding-3-small'),
      chat_model: ENV.fetch('OPENAI_CHAT_MODEL', 'gpt-4.1-mini')
    )
  end

  # Anthropic (Alternative)
  if ENV['ANTHROPIC_API_KEY'].present?
    config.add_provider(:anthropic, Prescient::Provider::Anthropic,
      api_key: ENV['ANTHROPIC_API_KEY'],
      model: ENV.fetch('ANTHROPIC_MODEL', 'claude-sonnet-4-20250514')
    )
  end

  # HuggingFace (Research/Open Source)
  if ENV['HUGGINGFACE_API_KEY'].present?
    config.add_provider(:huggingface, Prescient::Provider::HuggingFace,
      api_key: ENV['HUGGINGFACE_API_KEY'],
      embedding_model: ENV.fetch('HUGGINGFACE_EMBEDDING_MODEL', 'sentence-transformers/all-MiniLM-L6-v2'),
      chat_model: ENV.fetch('HUGGINGFACE_CHAT_MODEL', 'google/gemma-2-2b-it')
    )
  end

  # Google Gemini
  if ENV['GEMINI_API_KEY'].present?
    config.add_provider(:gemini, Prescient::Provider::Gemini,
      api_key: ENV['GEMINI_API_KEY'],
      embedding_model: ENV.fetch('GEMINI_EMBEDDING_MODEL', 'gemini-embedding-001'),
      chat_model: ENV.fetch('GEMINI_CHAT_MODEL', 'gemini-2.5-flash')
    )
  end

  # Mistral
  if ENV['MISTRAL_API_KEY'].present?
    config.add_provider(:mistral, Prescient::Provider::Mistral,
      api_key: ENV['MISTRAL_API_KEY'],
      embedding_model: ENV.fetch('MISTRAL_EMBEDDING_MODEL', 'mistral-embed'),
      chat_model: ENV.fetch('MISTRAL_CHAT_MODEL', 'mistral-large-latest')
    )
  end

  # DeepSeek supports generation, but not embeddings.
  if ENV['DEEPSEEK_API_KEY'].present?
    config.add_provider(:deepseek, Prescient::Provider::DeepSeek,
      api_key: ENV['DEEPSEEK_API_KEY'],
      chat_model: ENV.fetch('DEEPSEEK_CHAT_MODEL', 'deepseek-v4-flash')
    )
  end

  # xAI supports generation, but not embeddings.
  if ENV['XAI_API_KEY'].present?
    config.add_provider(:xai, Prescient::Provider::XAI,
      api_key: ENV['XAI_API_KEY'],
      chat_model: ENV.fetch('XAI_CHAT_MODEL', 'grok-4.5')
    )
  end
end

# Set default provider for Rails
Rails.application.config.default_ai_provider = :ollama
```

For YAML-based deployments, use the versioned configuration format and keep
credentials in environment variables:

```ruby
Prescient.load_configuration('prescient.yml')
```

Configuration precedence is CLI overrides, environment defaults and
references, YAML values, then built-in defaults. The generated
`prescient config example` file includes the current JSON Schema URL.

### 4. Mount the REST API

`Prescient::API` is Rack-compatible and can be mounted directly in a Rails
route set. The API keeps provider execution on `Prescient::Client` and exposes
only generic operations:

```ruby
# config/routes.rb
prescient_api = Prescient::API.new(
  authentication: lambda { |env|
    expected_token = ENV.fetch('PRESCIENT_API_TOKEN', nil)
    expected_token && env['HTTP_AUTHORIZATION'] == "Bearer #{expected_token}"
  }
)

mount prescient_api => '/prescient', as: :prescient_api
```

This makes the following routes available under `/prescient`:

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/healthz` | Liveness check |
| `GET` | `/readyz` | Readiness check |
| `GET` | `/v1/version` | Library and API versions |
| `GET` | `/v1/providers` | Configured providers |
| `GET` | `/v1/models` | Available models, optionally filtered by provider |
| `GET` | `/v1/capabilities` | Provider capabilities |
| `GET` | `/v1/health` | Provider health |
| `POST` | `/v1/generate` | Text generation |
| `POST` | `/v1/search` | Normalized external-tool search |
| `POST` | `/v1/search/generate` | Search with opt-in AI generation |
| `POST` | `/v1/agent` | Bounded allowlisted tool-calling agent |
| `POST` | `/v1/embeddings` | Single embedding |
| `POST` | `/v1/embeddings/batch` | Bounded batch embeddings |

For example:

```bash
curl http://localhost:3000/prescient/healthz

curl -X POST http://localhost:3000/prescient/v1/generate \
  -H "Authorization: Bearer ${PRESCIENT_API_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Explain Ruby fibers"}'

curl -X POST http://localhost:3000/prescient/v1/search/generate \
  -H "Authorization: Bearer ${PRESCIENT_API_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"query":"Ruby HTTP clients","provider":"openai","limit":5}'

curl -X POST http://localhost:3000/prescient/v1/search \
  -H "Authorization: Bearer ${PRESCIENT_API_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"query":"Ruby HTTP clients","limit":5}'

curl -X POST http://localhost:3000/prescient/v1/agent \
  -H "Authorization: Bearer ${PRESCIENT_API_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Summarize account status","provider":"openai","tools":[]}'
```

Responses include a request ID. Request bodies are size-limited, batch inputs
are bounded, and JSON errors do not expose raw provider response bodies. Keep
the API behind the application’s normal TLS, authentication, rate-limiting,
and observability controls.

### 5. Update Environment Variables

```bash
# .env or environment configuration

# Ollama (Local)
OLLAMA_URL=http://localhost:11434
OLLAMA_EMBEDDING_MODEL=nomic-embed-text
OLLAMA_CHAT_MODEL=llama3.2:3b

# OpenAI (Production)
OPENAI_API_KEY=your_openai_api_key
OPENAI_EMBEDDING_MODEL=text-embedding-3-small
OPENAI_CHAT_MODEL=gpt-4.1-mini

# Anthropic (Alternative)
ANTHROPIC_API_KEY=your_anthropic_api_key
ANTHROPIC_MODEL=claude-sonnet-4-20250514

# HuggingFace (Research)
HUGGINGFACE_API_KEY=your_huggingface_api_key
HUGGINGFACE_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
HUGGINGFACE_CHAT_MODEL=google/gemma-2-2b-it

# Google Gemini
GEMINI_API_KEY=your_gemini_api_key
GEMINI_EMBEDDING_MODEL=gemini-embedding-001
GEMINI_CHAT_MODEL=gemini-2.5-flash

# Mistral
MISTRAL_API_KEY=your_mistral_api_key
MISTRAL_EMBEDDING_MODEL=mistral-embed
MISTRAL_CHAT_MODEL=mistral-large-latest

# DeepSeek (generation only)
DEEPSEEK_API_KEY=your_deepseek_api_key
DEEPSEEK_CHAT_MODEL=deepseek-v4-flash

# xAI (generation only)
XAI_API_KEY=your_xai_api_key
XAI_CHAT_MODEL=grok-4.5
```

### 6. Update Controllers

**Before:**

```ruby
class Api::V1::AiQueriesController < ApplicationController
  def create
    embedding = OllamaService.new.generate_embedding(params[:query])
    # ... rest of the logic
  end
end
```

**After:**

```ruby
class Api::V1::AiQueriesController < ApplicationController
  def create
    # Use default provider or specify one
    embedding = AIService.generate_embedding(params[:query])

    # Or use specific provider
    # embedding = AIService.generate_embedding(params[:query], provider: :openai)

    # ... rest of the logic remains the same
  end

  private

  def generate_ai_response(query, context_items)
    # Automatically uses configured provider with fallback
    response = AIService.generate_response(
      query,
      context_items,
      max_tokens: 2000,
      temperature: 0.7
    )

    response[:response]
  rescue Prescient::Error => e
    Rails.logger.error "AI response failed: #{e.message}"
    "I apologize, but I'm currently unable to generate a response. Please try again later."
  end
end
```

### 7. Health Check Integration

```ruby
# app/controllers/api/v1/system/health_controller.rb
class Api::V1::System::HealthController < ApplicationController
  def show
    health_status = {
      database: database_health,
      prescient: prescient_health,
      overall: 'healthy'
    }

    # Set overall status based on critical components
    if health_status[:prescient][:primary][:status] != 'healthy'
      health_status[:overall] = 'degraded'
    end

    render json: health_status
  end

  private

  def prescient_health
    providers = {}

    # Check primary provider
    primary_provider = Rails.application.config.default_ai_provider
    providers[:primary] = {
      name: primary_provider,
      **AIService.health_check(provider: primary_provider)
    }

    # Check backup providers
    backup_providers = %i[openai anthropic huggingface gemini mistral deepseek xai] - [primary_provider]
    providers[:backups] = backup_providers.map do |provider|
      {
        name: provider,
        **AIService.health_check(provider: provider)
      }
    end

    providers
  end

  def database_health
    ActiveRecord::Base.connection.execute('SELECT 1')
    { status: 'healthy' }
  rescue StandardError => e
    { status: 'unhealthy', error: e.message }
  end
end
```

### 8. Migration Strategy

1. **Phase 1: Side-by-side deployment**

   - Keep existing OllamaService
   - Add Prescient alongside
   - Test thoroughly in development

2. **Phase 2: Gradual migration**

   - Update one controller at a time
   - Use feature flags to switch between old/new systems
   - Monitor performance and error rates

3. **Phase 3: Complete migration**
   - Remove old OllamaService
   - Update all controllers to use AIService
   - Clean up unused code

### 9. Testing Updates

```ruby
# test/services/ai_service_test.rb
class AIServiceTest < ActiveSupport::TestCase
  setup do
    Prescient.configure do |config|
      config.add_provider(:test, Prescient::Provider::Ollama,
        url: 'http://localhost:11434',
        embedding_model: 'test-embed',
        chat_model: 'test-chat'
      )
      config.default_provider = :test
    end
  end

  test 'generate_embedding returns an embedding vector' do
    Prescient.stub(:generate_embedding, [0.1, 0.2, 0.3]) do
      result = Prescient.generate_embedding('test text', provider: :test, enable_fallback: false)
      assert_equal [0.1, 0.2, 0.3], result
    end
  end
end
```

### 10. Monitoring and Logging

```ruby
# config/initializers/prescient_monitoring.rb
class PrescientMonitoring
  def self.setup!
    ActiveSupport::Notifications.subscribe('prescient.request') do |name, start, finish, id, payload|
      duration = finish - start

      Rails.logger.info "AI Provider Request: #{payload[:provider]} - #{payload[:operation]} - #{duration.round(3)}s"

      # Send metrics to your monitoring system
      # StatsD.increment('prescient.requests', tags: [
      #   "provider:#{payload[:provider]}",
      #   "operation:#{payload[:operation]}",
      #   "status:#{payload[:status]}"
      # ])
    end
  end
end

PrescientMonitoring.setup! if Rails.env.production?
```

### 11. Performance Optimization

```ruby
# app/services/ai_service.rb (enhanced)
class AIService
  # Connection pooling for providers
  def self.client(provider = nil)
    @clients ||= {}
    provider_name = provider || Rails.application.config.default_ai_provider

    @clients[provider_name] ||= begin
      # Use connection pooling for high-traffic applications
      Prescient.client(provider_name)
    end
  end

  # Caching for embeddings (optional)
  def self.generate_embedding(text, provider: nil)
    cache_key = "ai_embedding:#{ Digest::SHA256.hexdigest(text)}:#{ provider}"

    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      client(provider).generate_embedding(text)
    end
  rescue Prescient::Error => e
    Rails.logger.error "AI embedding generation failed: #{e.message}"
    raise
  end
end
```

## Benefits of Migration

1. **Provider Flexibility**: Easy switching between AI providers
2. **Fallback Support**: Automatic fallback to backup providers
3. **Better Error Handling**: Comprehensive error classification
4. **Monitoring**: Built-in health checks and metrics
5. **Testing**: Easier mocking and testing
6. **Scalability**: Better support for different deployment scenarios
7. **Cost Optimization**: Use local models for development, cloud for production

## Rollback Plan

If issues arise, quickly rollback by:

1. Revert initializer changes
2. Switch controllers back to OllamaService
3. Deploy previous version
4. Debug issues separately

The gem structure allows for easy rollback since it's designed as a drop-in replacement.
