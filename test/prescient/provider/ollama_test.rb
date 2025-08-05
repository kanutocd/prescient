# frozen_string_literal: true

require 'test_helper'

class OllamaProviderTest < PrescientTest
  def setup
    super
    @provider = Prescient::Provider::Ollama.new(
      url:             'http://localhost:11434',
      embedding_model: 'nomic-embed-text',
      chat_model:      'llama3.1:8b',
      timeout:         30,
    )
  end

  def test_initialize_sets_configuration
    assert_equal 'http://localhost:11434', @provider.options[:url]
    assert_equal 'nomic-embed-text', @provider.options[:embedding_model]
    assert_equal 'llama3.1:8b', @provider.options[:chat_model]
    assert_equal 30, @provider.options[:timeout]
  end

  def test_initialize_validates_required_options
    assert_raises(Prescient::Error) do
      Prescient::Provider::Ollama.new(embedding_model: 'test')
    end

    assert_raises(Prescient::Error) do
      Prescient::Provider::Ollama.new(url: 'http://localhost:11434')
    end
  end

  def test_generate_embedding_success
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({ 'embedding' => Array.new(768) { |i| i * 0.001 } })

    @provider.class.expects(:post).returns(mock_response)

    result = @provider.generate_embedding('test text')

    assert_equal 768, result.length
    assert_instance_of Float, result.first
  end

  def test_generate_embedding_normalizes_dimensions
    # Mock response with more dimensions than expected
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'embedding' => Array.new(1000) { |i| i * 0.1 },
    })

    @provider.class.expects(:post).returns(mock_response)

    result = @provider.generate_embedding('test text')

    # Should be normalized to 768 dimensions
    assert_equal 768, result.length
  end

  def test_generate_embedding_handles_missing_response
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({})

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::InvalidResponseError) do
      @provider.generate_embedding('test text')
    end
  end

  def test_generate_embedding_handles_http_errors
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(false)
    mock_response.stubs(:code).returns(404)
    mock_response.stubs(:message).returns('Not Found')

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::ModelNotAvailableError) do
      @provider.generate_embedding('test text')
    end
  end

  def test_generate_response_success
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'response'          => 'This is a test response',
      'total_duration'    => 1_500_000_000,
      'eval_count'        => 25,
      'eval_duration'     => 1_000_000_000,
      'prompt_eval_count' => 10,
    })

    @provider.class.expects(:post).returns(mock_response)

    result = @provider.generate_response('test prompt')

    assert_equal 'This is a test response', result[:response]
    assert_equal 'llama3.1:8b', result[:model]
    assert_equal 'ollama', result[:provider]
    assert_in_delta 1.5, result[:processing_time]
    assert_equal 25, result[:metadata][:eval_count]
  end

  def test_generate_response_with_context_items
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({ 'response' => 'Response with context' })

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
    mock_response.stubs(:parsed_response).returns({ 'response' => 'Custom response' })

    # Verify options are passed correctly
    @provider.class.expects(:post).with(
      '/api/generate',
      has_entries(body: regexp_matches(/num_predict.*1000/)),
    ).returns(mock_response)

    @provider.generate_response('test', [], max_tokens: 1000, temperature: 0.8, top_p: 0.95)
  end

  def test_health_check_success
    mock_models_response = mock('models_response')
    mock_models_response.stubs(:success?).returns(true)
    mock_models_response.stubs(:parsed_response).returns({
      'models' => [
        { 'name' => 'nomic-embed-text', 'size' => 274_000_000 },
        { 'name' => 'llama3.1:8b', 'size' => 4_700_000_000 },
      ],
    })

    @provider.class.expects(:get).returns(mock_models_response)

    result = @provider.health_check

    assert_equal 'healthy', result[:status]
    assert_equal 'ollama', result[:provider]
    assert_equal 'http://localhost:11434', result[:url]
    assert_includes result[:models_available], 'nomic-embed-text'
    assert_includes result[:models_available], 'llama3.1:8b'
  end

  def test_health_check_handles_errors
    @provider.class.expects(:get).raises(StandardError.new('Connection failed'))

    result = @provider.health_check

    assert_equal 'unavailable', result[:status]
    assert_equal 'ollama', result[:provider]
    assert_equal 'Prescient::Error', result[:error]
    assert_equal 'Unexpected error: Connection failed', result[:message]
  end

  def test_available_models_success
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'models' => [
        {
          'name'        => 'nomic-embed-text',
          'size'        => 274_000_000,
          'modified_at' => '2024-01-01T00:00:00Z',
          'digest'      => 'abc123',
        },
      ],
    })

    @provider.class.expects(:get).returns(mock_response)

    result = @provider.available_models

    assert_equal 1, result.length
    assert_equal 'nomic-embed-text', result.first[:name]
    assert_equal 274_000_000, result.first[:size]
    assert result.first[:embedding]
    refute result.first[:chat]
  end

  def test_pull_model_success
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({})

    @provider.class.expects(:post).with(
      '/api/pull',
      has_entries(
        headers: { 'Content-Type' => 'application/json' },
        body:    '{"name":"test-model"}',
        timeout: 300,
      ),
    ).returns(mock_response)

    result = @provider.pull_model('test-model')

    assert result[:success]
    assert_equal 'test-model', result[:model]
    assert_includes result[:message], 'pulled successfully'
  end

  def test_clean_text_helper
    # Test the inherited clean_text method
    assert_equal '', @provider.send(:clean_text, nil)
    assert_equal '', @provider.send(:clean_text, '')
    assert_equal 'hello world', @provider.send(:clean_text, '  hello    world  ')

    # Test length limiting
    long_text = 'a' * 10000
    cleaned = @provider.send(:clean_text, long_text)

    assert_equal 8000, cleaned.length
  end

  def test_normalize_embedding_helper
    # Test dimension normalization
    embedding = [0.1, 0.2, 0.3]
    result = @provider.send(:normalize_embedding, embedding, 5)

    assert_equal 5, result.length
    assert_equal [0.1, 0.2, 0.3, 0.0, 0.0], result

    # Test truncation
    long_embedding = Array.new(1000) { |i| i * 0.1 }
    result = @provider.send(:normalize_embedding, long_embedding, 768)

    assert_equal 768, result.length
  end

  def test_build_prompt_without_context
    prompt = @provider.send(:build_prompt, 'What is Ruby?')

    assert_includes prompt, 'What is Ruby?'
    assert_includes prompt, 'helpful AI assistant'
  end

  def test_build_prompt_with_context
    context_items = [
      { 'title' => 'Ruby Guide', 'content' => 'Ruby is a programming language' },
    ]

    prompt = @provider.send(:build_prompt, 'What is Ruby?', context_items)

    assert_includes prompt, 'What is Ruby?'
    assert_includes prompt, 'Ruby Guide'
    assert_includes prompt, 'Ruby is a programming language'
  end

  def test_error_handling_wrapper
    # Test that handle_errors properly wraps exceptions
    result = @provider.send(:handle_errors) { 'success' }

    assert_equal 'success', result

    assert_raises(Prescient::ConnectionError) do
      @provider.send(:handle_errors) { raise Net::ReadTimeout, 'timeout' }
    end

    assert_raises(Prescient::InvalidResponseError) do
      @provider.send(:handle_errors) { raise JSON::ParserError, 'invalid json' }
    end
  end
end
