# frozen_string_literal: true

require 'test_helper'

class IntegrationTest < PrescientTest
  def setup
    super
    # Reset configuration for clean test state
    Prescient.reset_configuration!
  end

  def teardown
    Prescient.reset_configuration!
    super
  end

  def test_configuration_and_client_creation
    # Test the full configuration -> client creation flow
    Prescient.configure do |config|
      config.default_provider = :test_ollama
      config.timeout = 45
      config.retry_attempts = 5

      config.add_provider(:test_ollama, MockOllamaProvider,
                          url:             'http://localhost:11434',
                          embedding_model: 'nomic-embed-text',
                          chat_model:      'llama3.1:8b')
    end

    # Test configuration was applied
    assert_equal :test_ollama, Prescient.configuration.default_provider
    assert_equal 45, Prescient.configuration.timeout
    assert_equal 5, Prescient.configuration.retry_attempts

    # Test client creation
    client = Prescient.client

    assert_instance_of MockOllamaProvider, client.provider
    assert_equal :test_ollama, client.provider_name

    # Test explicit provider selection
    explicit_client = Prescient.client(:test_ollama)

    assert_instance_of MockOllamaProvider, explicit_client.provider
  end

  def test_multiple_providers_configuration
    Prescient.configure do |config|
      config.add_provider(:mock_ollama, MockOllamaProvider,
                          url:             'http://localhost:11434',
                          embedding_model: 'nomic-embed-text',
                          chat_model:      'llama3.1:8b')

      config.add_provider(:mock_openai, MockOpenAIProvider,
                          api_key:         'test-key',
                          embedding_model: 'text-embedding-3-small',
                          chat_model:      'gpt-3.5-turbo')

      config.add_provider(:mock_anthropic, MockAnthropicProvider,
                          api_key: 'test-key',
                          model:   'claude-3-haiku-20240307')
    end

    # Test each provider can be instantiated
    ollama_client = Prescient.client(:mock_ollama)
    openai_client = Prescient.client(:mock_openai)
    anthropic_client = Prescient.client(:mock_anthropic)

    assert_instance_of MockOllamaProvider, ollama_client.provider
    assert_instance_of MockOpenAIProvider, openai_client.provider
    assert_instance_of MockAnthropicProvider, anthropic_client.provider
  end

  def test_embedding_and_response_generation_flow
    Prescient.configure do |config|
      config.add_provider(:mock_provider, MockFullProvider,
                          test_option: 'test_value')
    end

    client = Prescient.client(:mock_provider)

    # Test embedding generation
    embedding = client.generate_embedding('test document content')

    assert_instance_of Array, embedding
    assert_equal 768, embedding.length
    assert(embedding.all?(Float))

    # Test response generation without context
    response = client.generate_response('What is machine learning?')

    assert_instance_of Hash, response
    assert_includes response.keys, :response
    assert_includes response.keys, :model
    assert_includes response.keys, :provider

    # Test response generation with context
    context_items = [
      { 'title' => 'ML Guide', 'content' => 'Machine learning is...' },
      { 'title' => 'AI Overview', 'content' => 'Artificial intelligence...' },
    ]

    contextual_response = client.generate_response(
      'Explain machine learning',
      context_items,
      temperature: 0.7,
      max_tokens:  500,
    )

    assert_instance_of Hash, contextual_response
    assert_includes contextual_response[:response], 'context'
  end

  def test_health_check_and_availability
    Prescient.configure do |config|
      config.add_provider(:healthy_provider, MockHealthyProvider)
      config.add_provider(:unhealthy_provider, MockUnhealthyProvider)
    end

    healthy_client = Prescient.client(:healthy_provider)
    unhealthy_client = Prescient.client(:unhealthy_provider)

    # Test healthy provider
    health = healthy_client.health_check

    assert_equal 'healthy', health[:status]
    assert_predicate healthy_client, :available?

    # Test unhealthy provider
    unhealthy_health = unhealthy_client.health_check

    assert_equal 'unhealthy', unhealthy_health[:status]
    refute_predicate unhealthy_client, :available?
  end

  def test_error_handling_across_providers
    Prescient.configure do |config|
      config.add_provider(:error_provider, MockErrorProvider)
    end

    client = Prescient.client(:error_provider)

    # Test different error types
    assert_raises(Prescient::ConnectionError) do
      client.generate_embedding('connection_error')
    end

    assert_raises(Prescient::AuthenticationError) do
      client.generate_embedding('auth_error')
    end

    assert_raises(Prescient::RateLimitError) do
      client.generate_embedding('rate_limit_error')
    end

    assert_raises(Prescient::InvalidResponseError) do
      client.generate_embedding('invalid_response_error')
    end
  end

  def test_prompt_template_integration
    Prescient.configure do |config|
      config.add_provider(:template_provider, MockTemplateProvider,
                          prompt_templates: {
                            system_prompt:         'You are a helpful test assistant.',
                            no_context_template:   'System: %<system_prompt>s\nUser: %<query>s',
                            with_context_template: 'System: %<system_prompt>s\nContext: %<context>s\nUser: %<query>s',
                          })
    end

    client = Prescient.client(:template_provider)

    # Test without context
    response = client.generate_response('Hello')

    assert_includes response[:used_prompt], 'helpful test assistant'
    assert_includes response[:used_prompt], 'Hello'
    refute_includes response[:used_prompt], 'Context:'

    # Test with context
    context_response = client.generate_response('Hello', [{ 'info' => 'test context' }])

    assert_includes context_response[:used_prompt], 'helpful test assistant'
    assert_includes context_response[:used_prompt], 'Hello'
    assert_includes context_response[:used_prompt], 'Context:'
    assert_includes context_response[:used_prompt], 'test context'
  end

  def test_context_formatting_integration
    Prescient.configure do |config|
      config.add_provider(:context_provider, MockContextProvider,
                          context_configs: {
                            'document' => {
                              fields:           ['title', 'content', 'author'],
                              format:           '%<title>s by %<author>s: %<content>s',
                              embedding_fields: ['title', 'content'],
                            },
                          })
    end

    client = Prescient.client(:context_provider)

    context_items = [
      {
        'type'       => 'document',
        'title'      => 'AI Guide',
        'content'    => 'Introduction to AI',
        'author'     => 'John Doe',
        'created_at' => '2024-01-01',
      },
    ]

    response = client.generate_response('What is AI?', context_items)

    # Check that context was formatted according to configuration
    assert_includes response[:formatted_context], 'AI Guide by John Doe: Introduction to AI'
    refute_includes response[:formatted_context], '2024-01-01' # created_at not in fields
  end

  def test_module_level_convenience_methods
    Prescient.configure do |config|
      config.default_provider = :mock_provider
      config.add_provider(:mock_provider, MockFullProvider)
    end

    # Test module-level methods
    embedding = Prescient.generate_embedding('test text')

    assert_instance_of Array, embedding

    response = Prescient.generate_response('test prompt')

    assert_instance_of Hash, response

    health = Prescient.health_check

    assert_instance_of Hash, health

    # Test with explicit provider
    explicit_response = Prescient.generate_response('test', [], provider: :mock_provider)

    assert_instance_of Hash, explicit_response
  end

  # Mock provider classes for testing

  class MockOllamaProvider < Prescient::Base
    def generate_embedding(_text, **_options)
      Array.new(768) { rand }
    end

    def generate_response(prompt, _context_items = [], **_options)
      { response: "Ollama response to: #{prompt}", model: 'llama3.1:8b', provider: 'ollama' }
    end

    def health_check
      { status: 'healthy', provider: 'ollama' }
    end
  end

  class MockOpenAIProvider < Prescient::Base
    def generate_embedding(_text, **_options)
      Array.new(1536) { rand }
    end

    def generate_response(prompt, _context_items = [], **_options)
      { response: "OpenAI response to: #{prompt}", model: 'gpt-3.5-turbo', provider: 'openai' }
    end

    def health_check
      { status: 'healthy', provider: 'openai' }
    end
  end

  class MockAnthropicProvider < Prescient::Base
    def generate_embedding(_text, **_options)
      raise Prescient::Error, 'Anthropic does not support embeddings'
    end

    def generate_response(prompt, _context_items = [], **_options)
      { response: "Claude response to: #{prompt}", model: 'claude-3-haiku', provider: 'anthropic' }
    end

    def health_check
      { status: 'healthy', provider: 'anthropic' }
    end
  end

  class MockFullProvider < Prescient::Base
    def generate_embedding(_text, **_options)
      Array.new(768) { rand }
    end

    def generate_response(prompt, context_items = [], **_options)
      response_text = "Response to: #{prompt}"
      response_text += ' with context' if context_items.any?

      { response: response_text, model: 'test-model', provider: 'mock' }
    end

    def health_check
      { status: 'healthy', provider: 'mock', ready: true }
    end
  end

  class MockHealthyProvider < Prescient::Base
    def generate_embedding(_text, **_options) = [0.1, 0.2, 0.3]
    def generate_response(_prompt, _context_items = [], **_options) = { response: 'healthy' }
    def health_check = { status: 'healthy', provider: 'healthy' }
  end

  class MockUnhealthyProvider < Prescient::Base
    def generate_embedding(_text, **_options) = raise(Prescient::ConnectionError, 'Unavailable')
    def generate_response(_prompt, _context_items = [], **_options) = raise(Prescient::ConnectionError, 'Unavailable')
    def health_check = { status: 'unhealthy', provider: 'unhealthy' }
    def available? = false
  end

  class MockErrorProvider < Prescient::Base
    def generate_embedding(text, **_options)
      case text
      when 'connection_error'
        raise Prescient::ConnectionError, 'Connection failed'
      when 'auth_error'
        raise Prescient::AuthenticationError, 'Authentication failed'
      when 'rate_limit_error'
        raise Prescient::RateLimitError, 'Rate limit exceeded'
      when 'invalid_response_error'
        raise Prescient::InvalidResponseError, 'Invalid response'
      else
        [0.1, 0.2, 0.3]
      end
    end

    def generate_response(_prompt, _context_items = [], **_options) = { response: 'test' }
    def health_check = { status: 'healthy' }
  end

  class MockTemplateProvider < Prescient::Base
    def generate_embedding(_text, **_options) = [0.1, 0.2, 0.3]

    def generate_response(prompt, context_items = [], **_options)
      used_prompt = build_prompt(prompt, context_items)
      { response: 'Template response', used_prompt: used_prompt }
    end

    def health_check = { status: 'healthy' }
  end

  class MockContextProvider < Prescient::Base
    def generate_embedding(_text, **_options) = [0.1, 0.2, 0.3]

    def generate_response(_prompt, context_items = [], **_options)
      formatted_context = context_items.map { |item| format_context_item(item) }.join("\n")
      { response: 'Context response', formatted_context: formatted_context }
    end

    def health_check = { status: 'healthy' }
  end
end
