# frozen_string_literal: true

require 'test_helper'

class HuggingFaceProviderTest < PrescientTest
  def setup
    super
    @provider = Prescient::Provider::HuggingFace.new(
      api_key:         'test-api-key',
      embedding_model: 'sentence-transformers/all-MiniLM-L6-v2',
      chat_model:      'microsoft/DialoGPT-medium',
      timeout:         30,
    )
  end

  def test_initialize_sets_configuration
    assert_equal 'test-api-key', @provider.options[:api_key]
    assert_equal 'sentence-transformers/all-MiniLM-L6-v2', @provider.options[:embedding_model]
    assert_equal 'microsoft/DialoGPT-medium', @provider.options[:chat_model]
    assert_equal 30, @provider.options[:timeout]
  end

  def test_initialize_validates_required_options
    assert_raises(Prescient::Error) do
      Prescient::Provider::HuggingFace.new(embedding_model: 'test')
    end

    assert_raises(Prescient::Error) do
      Prescient::Provider::HuggingFace.new(api_key: 'test')
    end
  end

  def test_embedding_dimensions_constant
    assert_equal 384, Prescient::Provider::HuggingFace::EMBEDDING_DIMENSIONS['sentence-transformers/all-MiniLM-L6-v2']
    assert_equal 768, Prescient::Provider::HuggingFace::EMBEDDING_DIMENSIONS['sentence-transformers/all-mpnet-base-v2']
    assert_equal 1024, Prescient::Provider::HuggingFace::EMBEDDING_DIMENSIONS['sentence-transformers/all-roberta-large-v1']
  end

  def test_generate_embedding_success_with_nested_array
    # HuggingFace returns nested arrays
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns([
      Array.new(384) { |i| i * 0.001 },
    ])

    @provider.class.expects(:post).with(
      '/pipeline/feature-extraction/sentence-transformers/all-MiniLM-L6-v2',
      has_entries(
        headers: {
          'Content-Type'  => 'application/json',
          'Authorization' => 'Bearer test-api-key',
        },
      ),
    ).returns(mock_response)

    result = @provider.generate_embedding('test text')

    assert_equal 384, result.length
    assert_instance_of Float, result.first
  end

  def test_generate_embedding_success_with_flat_array
    # Some models return flat arrays
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns(Array.new(384) { |i| i * 0.001 })

    @provider.class.expects(:post).returns(mock_response)

    result = @provider.generate_embedding('test text')

    assert_equal 384, result.length
  end

  def test_generate_embedding_normalizes_dimensions
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns([[0.1, 0.2, 0.3]]) # Too few dimensions

    @provider.class.expects(:post).returns(mock_response)

    result = @provider.generate_embedding('test text')

    # Should be normalized to 384 dimensions (default for unknown models)
    assert_equal 384, result.length
    assert_equal [0.1, 0.2, 0.3] + Array.new(381, 0.0), result
  end

  def test_generate_embedding_handles_invalid_response
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns('invalid')

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::InvalidResponseError) do
      @provider.generate_embedding('test text')
    end
  end

  def test_generate_embedding_includes_wait_for_model
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns([[0.1, 0.2, 0.3]])

    @provider.class.expects(:post).with(
      anything,
      has_entries(
        body: regexp_matches(/"wait_for_model":true/),
      ),
    ).returns(mock_response)

    @provider.generate_embedding('test text')
  end

  def test_generate_response_success_with_array_response
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns([
      { 'generated_text' => 'This is a test response' },
    ])

    @provider.class.expects(:post).with(
      '/models/microsoft/DialoGPT-medium',
      has_entries(
        headers: {
          'Content-Type'  => 'application/json',
          'Authorization' => 'Bearer test-api-key',
        },
      ),
    ).returns(mock_response)

    result = @provider.generate_response('test prompt')

    assert_equal 'This is a test response', result[:response]
    assert_equal 'microsoft/DialoGPT-medium', result[:model]
    assert_equal 'huggingface', result[:provider]
    assert_nil result[:processing_time]
    assert_empty(result[:metadata])
  end

  def test_generate_response_success_with_hash_response
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'generated_text' => 'Hash response format',
    })

    @provider.class.expects(:post).returns(mock_response)

    result = @provider.generate_response('test prompt')

    assert_equal 'Hash response format', result[:response]
  end

  def test_generate_response_with_text_field
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'text' => 'Alternative text field',
    })

    @provider.class.expects(:post).returns(mock_response)

    result = @provider.generate_response('test prompt')

    assert_equal 'Alternative text field', result[:response]
  end

  def test_generate_response_with_context_items
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns([
      { 'generated_text' => 'Response with context' },
    ])

    @provider.class.expects(:post).returns(mock_response)

    context_items = [
      { 'title' => 'Test Doc', 'content' => 'Test content' },
    ]

    result = @provider.generate_response('test prompt', context_items)

    assert_equal 'Response with context', result[:response]
  end

  def test_generate_response_with_options
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns([{ 'generated_text' => 'Custom response' }])

    @provider.class.expects(:post).with(
      anything,
      has_entries(
        body: regexp_matches(/1000.*0\.8.*0\.95.*false/),
      ),
    ).returns(mock_response)

    @provider.generate_response('test', [], max_tokens: 1000, temperature: 0.8, top_p: 0.95)
  end

  def test_generate_response_handles_missing_text
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns([{ 'something_else' => 'no text field' }])

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::InvalidResponseError) do
      @provider.generate_response('test prompt')
    end
  end

  def test_health_check_success
    # Mock embedding model health check
    embedding_response = mock('embedding_response')
    embedding_response.stubs(:success?).returns(true)

    # Mock chat model health check
    chat_response = mock('chat_response')
    chat_response.stubs(:success?).returns(true)

    @provider.class.expects(:post).with(
      '/pipeline/feature-extraction/sentence-transformers/all-MiniLM-L6-v2',
      has_entries(
        headers: { 'Authorization' => 'Bearer test-api-key' },
        body:    '{"inputs":"test"}',
      ),
    ).returns(embedding_response)

    @provider.class.expects(:post).with(
      '/models/microsoft/DialoGPT-medium',
      has_entries(
        headers: { 'Authorization' => 'Bearer test-api-key' },
      ),
    ).returns(chat_response)

    result = @provider.health_check

    assert_equal 'healthy', result[:status]
    assert_equal 'huggingface', result[:provider]
    assert result[:embedding_model][:available]
    assert result[:chat_model][:available]
    assert result[:ready]
  end

  def test_health_check_partial_availability
    # Embedding works, chat fails
    embedding_response = mock('embedding_response')
    embedding_response.stubs(:success?).returns(true)

    chat_response = mock('chat_response')
    chat_response.stubs(:success?).returns(false)

    @provider.class.expects(:post).twice.returns(embedding_response, chat_response)

    result = @provider.health_check

    assert_equal 'partial', result[:status]
    assert result[:embedding_model][:available]
    refute result[:chat_model][:available]
    refute result[:ready]
  end

  def test_health_check_handles_connection_errors
    @provider.class.expects(:post).raises(Prescient::ConnectionError.new('Connection failed'))

    result = @provider.health_check

    assert_equal 'unavailable', result[:status]
    assert_equal 'huggingface', result[:provider]
    assert_equal 'Prescient::ConnectionError', result[:error]
    assert_equal 'Connection failed', result[:message]
  end

  def test_list_models_returns_configured_models
    result = @provider.list_models

    assert_equal 2, result.length

    embedding_model = result.find { |m| m[:type] == 'embedding' }

    assert embedding_model
    assert_equal 'sentence-transformers/all-MiniLM-L6-v2', embedding_model[:name]
    assert_equal 384, embedding_model[:dimensions]

    chat_model = result.find { |m| m[:type] == 'text-generation' }

    assert chat_model
    assert_equal 'microsoft/DialoGPT-medium', chat_model[:name]
  end

  def test_error_handling_for_different_status_codes
    # Test bad request
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(false)
    mock_response.stubs(:code).returns(400)
    mock_response.stubs(:body).returns('Bad request')

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::Error) do
      @provider.generate_embedding('test')
    end

    # Test authentication error
    mock_response.stubs(:code).returns(401)
    mock_response.stubs(:body).returns('Authentication failed')

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::AuthenticationError) do
      @provider.generate_embedding('test')
    end

    # Test rate limiting
    mock_response.stubs(:code).returns(429)
    mock_response.stubs(:body).returns('Rate limit exceeded')

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::RateLimitError) do
      @provider.generate_embedding('test')
    end

    # Test service unavailable with model loading
    mock_response.stubs(:code).returns(503)
    mock_response.stubs(:parsed_response).returns({ 'error' => 'Model is loading, please try again later' })

    @provider.class.expects(:post).returns(mock_response)

    error = assert_raises(Prescient::Error) {
      @provider.generate_embedding('test')
    }

    assert_includes error.message, 'Model is loading'

    # Test general service unavailable
    mock_response.stubs(:parsed_response).returns({ 'error' => 'Service temporarily unavailable' })

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::Error) do
      @provider.generate_embedding('test')
    end

    # Test server error
    mock_response.stubs(:code).returns(500)
    mock_response.stubs(:body).returns('Internal server error')

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::Error) do
      @provider.generate_embedding('test')
    end
  end

  def test_clean_text_preprocessing
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns([[0.1, 0.2, 0.3]])

    @provider.class.expects(:post).with(
      anything,
      has_entries(
        body: regexp_matches(/"inputs":"test text"/),
      ),
    ).returns(mock_response)

    @provider.generate_embedding("  test   text  \n")
  end

  def test_wait_for_model_parameter
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns([{ 'generated_text' => 'response' }])

    @provider.class.expects(:post).with(
      anything,
      has_entries(
        body: regexp_matches(/"wait_for_model":true/),
      ),
    ).returns(mock_response)

    @provider.generate_response('test')
  end
end
