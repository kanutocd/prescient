# Prescient

Prescient provides a unified interface for AI providers including Ollama (local), Anthropic Claude, OpenAI GPT, and HuggingFace models. Built for prescient applications that need AI predictions with provider switching, error handling, and fallback mechanisms.

## Features

- **Unified Interface**: Single API for multiple AI providers
- **Local and Cloud Support**: Ollama for local/private deployments, cloud APIs for scale
- **Embedding Generation**: Vector embeddings for semantic search and AI applications
- **Text Completion**: Chat completions with context support
- **Error Handling**: Robust error handling with automatic retries
- **Health Monitoring**: Built-in health checks for all providers
- **Flexible Configuration**: Environment variable and programmatic configuration

## Supported Providers

### Ollama (Local)

- **Models**: Any Ollama-compatible model (llama3.1, nomic-embed-text, etc.)
- **Capabilities**: Embeddings, Text Generation, Model Management
- **Use Case**: Privacy-focused, local deployments

### Anthropic Claude

- **Models**: Claude 3 (Haiku, Sonnet, Opus)
- **Capabilities**: Text Generation only (no embeddings)
- **Use Case**: High-quality conversational AI

### OpenAI

- **Models**: GPT-3.5, GPT-4, text-embedding-3-small/large
- **Capabilities**: Embeddings, Text Generation
- **Use Case**: Proven performance, wide model selection

### HuggingFace

- **Models**: sentence-transformers, open-source chat models
- **Capabilities**: Embeddings, Text Generation
- **Use Case**: Open-source models, research

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'prescient'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install prescient
```

## Configuration

### Environment Variables

```bash
# Ollama (Local)
OLLAMA_URL=http://localhost:11434
OLLAMA_EMBEDDING_MODEL=nomic-embed-text
OLLAMA_CHAT_MODEL=llama3.1:8b

# Anthropic
ANTHROPIC_API_KEY=your_api_key
ANTHROPIC_MODEL=claude-3-haiku-20240307

# OpenAI
OPENAI_API_KEY=your_api_key
OPENAI_EMBEDDING_MODEL=text-embedding-3-small
OPENAI_CHAT_MODEL=gpt-3.5-turbo

# HuggingFace
HUGGINGFACE_API_KEY=your_api_key
HUGGINGFACE_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
HUGGINGFACE_CHAT_MODEL=microsoft/DialoGPT-medium
```

### Programmatic Configuration

```ruby
require 'prescient'

# Configure providers
Prescient.configure do |config|
  config.default_provider = :ollama
  config.timeout = 60
  config.retry_attempts = 3
  config.retry_delay = 1.0

  # Add custom Ollama configuration
  config.add_provider(:ollama, Prescient::Ollama::Provider,
    url: 'http://localhost:11434',
    embedding_model: 'nomic-embed-text',
    chat_model: 'llama3.1:8b'
  )

  # Add Anthropic
  config.add_provider(:anthropic, Prescient::Anthropic::Provider,
    api_key: ENV['ANTHROPIC_API_KEY'],
    model: 'claude-3-haiku-20240307'
  )

  # Add OpenAI
  config.add_provider(:openai, Prescient::OpenAI::Provider,
    api_key: ENV['OPENAI_API_KEY'],
    embedding_model: 'text-embedding-3-small',
    chat_model: 'gpt-3.5-turbo'
  )
end
```

## Usage

### Quick Start

```ruby
require 'prescient'

# Use default provider (Ollama)
client = Prescient.client

# Generate embeddings
embedding = client.generate_embedding("Your text here")
# => [0.1, 0.2, 0.3, ...] (768-dimensional vector)

# Generate text responses
response = client.generate_response("What is Ruby?")
puts response[:response]
# => "Ruby is a dynamic, open-source programming language..."

# Health check
health = client.health_check
puts health[:status] # => "healthy"
```

### Provider-Specific Usage

```ruby
# Use specific provider
openai_client = Prescient.client(:openai)
anthropic_client = Prescient.client(:anthropic)

# Direct method calls
embedding = Prescient.generate_embedding("text", provider: :openai)
response = Prescient.generate_response("prompt", provider: :anthropic)
```

### Context-Aware Generation

```ruby
# Generate embeddings for document chunks
documents = ["Document 1 content", "Document 2 content"]
embeddings = documents.map { |doc| Prescient.generate_embedding(doc) }

# Later, find relevant context and generate response
query = "What is mentioned about Ruby?"
context_items = find_relevant_documents(query, embeddings) # Your similarity search

response = Prescient.generate_response(query, context_items,
  max_tokens: 1000,
  temperature: 0.7
)

puts response[:response]
puts "Model: #{response[:model]}"
puts "Provider: #{response[:provider]}"
```

### Error Handling

```ruby
begin
  response = client.generate_response("Your prompt")
rescue Prescient::ConnectionError => e
  puts "Connection failed: #{e.message}"
rescue Prescient::RateLimitError => e
  puts "Rate limited: #{e.message}"
rescue Prescient::AuthenticationError => e
  puts "Auth failed: #{e.message}"
rescue Prescient::Error => e
  puts "General error: #{e.message}"
end
```

### Health Monitoring

```ruby
# Check all providers
[:ollama, :anthropic, :openai, :huggingface].each do |provider|
  health = Prescient.health_check(provider: provider)
  puts "#{provider}: #{health[:status]}"
  puts "Ready: #{health[:ready]}" if health[:ready]
end
```

## Custom Prompt Templates

Prescient allows you to customize the AI assistant's behavior through configurable prompt templates:

```ruby
Prescient.configure do |config|
  config.add_provider(:customer_service, Prescient::Provider::OpenAI,
    api_key: ENV['OPENAI_API_KEY'],
    embedding_model: 'text-embedding-3-small',
    chat_model: 'gpt-3.5-turbo',
    prompt_templates: {
      system_prompt: 'You are a friendly customer service representative.',
      no_context_template: <<~TEMPLATE.strip,
        %{system_prompt}

        Customer Question: %{query}

        Please provide a helpful response.
      TEMPLATE
      with_context_template: <<~TEMPLATE.strip
        %{system_prompt} Use the company info below to help answer.

        Company Information:
        %{context}

        Customer Question: %{query}

        Respond based on our company policies above.
      TEMPLATE
    }
  )
end

client = Prescient.client(:customer_service)
response = client.generate_response("What's your return policy?")
```

### Template Placeholders

- `%{system_prompt}` - The system/role instruction
- `%{query}` - The user's question
- `%{context}` - Formatted context items (when provided)

### Template Types

- **system_prompt** - Defines the AI's role and behavior
- **no_context_template** - Used when no context items provided
- **with_context_template** - Used when context items are provided

### Examples by Use Case

#### Technical Documentation

```ruby
prompt_templates: {
  system_prompt: 'You are a technical documentation assistant. Provide detailed explanations with code examples.',
  # ... templates
}
```

#### Creative Writing

```ruby
prompt_templates: {
  system_prompt: 'You are a creative writing assistant. Be imaginative and inspiring.',
  # ... templates
}
```

See `examples/custom_prompts.rb` for complete examples.

## Custom Context Configurations

Define how different data types should be formatted and which fields to use for embeddings:

```ruby
Prescient.configure do |config|
  config.add_provider(:ecommerce, Prescient::Provider::OpenAI,
    api_key: ENV['OPENAI_API_KEY'],
    context_configs: {
      'product' => {
        fields: %w[name description price category brand],
        format: '%{name} by %{brand}: %{description} - $%{price} (%{category})',
        embedding_fields: %w[name description category brand]
      },
      'review' => {
        fields: %w[product_name rating review_text reviewer_name],
        format: '%{product_name} - %{rating}/5 stars: "%{review_text}"',
        embedding_fields: %w[product_name review_text]
      }
    }
  )
end

# Context items with explicit type
products = [
  {
    'type' => 'product',
    'name' => 'UltraBook Pro',
    'description' => 'High-performance laptop',
    'price' => '1299.99',
    'category' => 'Laptops',
    'brand' => 'TechCorp'
  }
]

client = Prescient.client(:ecommerce)
response = client.generate_response("I need a laptop for work", products)
```

### Context Configuration Options

- **fields** - Array of field names available for this context type
- **format** - Template string for displaying context items
- **embedding_fields** - Specific fields to use when generating embeddings

### Automatic Context Detection

The system automatically detects context types based on YOUR configured field patterns:

1. **Explicit Type Fields**: Uses `type`, `context_type`, or `model_type` field values
2. **Field Matching**: Matches items to configured contexts based on field overlap (≥50% match required)
3. **Default Fallback**: Uses generic formatting when no context configuration matches

The system has NO hardcoded context types - it's entirely driven by your configuration!

### Without Context Configuration

The system works perfectly without any context configuration - it will:

- Use intelligent fallback formatting for any hash structure
- Extract text fields for embeddings while excluding common metadata (id, timestamps, etc.)
- Provide consistent behavior across different data types

```ruby
# No context_configs needed - works with any data!
client = Prescient.client(:default)
response = client.generate_response("Analyze this", [
  { 'title' => 'Issue', 'content' => 'Server down', 'created_at' => '2024-01-01' },
  { 'name' => 'Alert', 'message' => 'High CPU usage', 'timestamp' => 1234567 }
])
```

See `examples/custom_contexts.rb` for complete examples.

## Advanced Usage

### Custom Provider Implementation

```ruby
class MyCustomProvider < Prescient::BaseProvider
  def generate_embedding(text, **options)
    # Your implementation
  end

  def generate_response(prompt, context_items = [], **options)
    # Your implementation
  end

  def health_check
    # Your implementation
  end

  protected

  def validate_configuration!
    # Validate required options
  end
end

# Register your provider
Prescient.configure do |config|
  config.add_provider(:mycustom, MyCustomProvider,
    api_key: 'your_key',
    model: 'your_model'
  )
end
```

### Provider Information

```ruby
client = Prescient.client(:ollama)
info = client.provider_info

puts info[:name]      # => :ollama
puts info[:class]     # => "Prescient::Ollama::Provider"
puts info[:available] # => true
puts info[:options]   # => {...} (excluding sensitive data)
```

## Provider-Specific Features

### Ollama

- Model management: `pull_model`, `list_models`
- Local deployment support
- No API costs

### Anthropic

- High-quality responses
- No embedding support (use with OpenAI/HuggingFace for embeddings)

### OpenAI

- Multiple embedding model sizes
- Latest GPT models
- Reliable performance

### HuggingFace

- Open-source models
- Research-friendly
- Free tier available

## Testing

The gem includes comprehensive test coverage:

```bash
bundle exec rspec
```

## Development

After checking out the repo, run:

```bash
bundle install
```

To install this gem onto your local machine:

```bash
bundle exec rake install
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Changelog

### Version 0.1.0

- Initial release
- Support for Ollama, Anthropic, OpenAI, and HuggingFace
- Unified interface for embeddings and text generation
- Comprehensive error handling and retry logic
- Health monitoring capabilities
