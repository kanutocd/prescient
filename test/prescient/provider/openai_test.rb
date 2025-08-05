# frozen_string_literal: true

require 'test_helper'

class OpenAIProviderTest < PrescientTest
  def setup
    super
    @provider = Prescient::Provider::OpenAI.new(
      api_key:         'test-api-key',
      embedding_model: 'text-embedding-3-small',
      chat_model:      'gpt-3.5-turbo',
      timeout:         30,
    )
  end

  def test_initialize_sets_configuration
    assert_equal 'test-api-key', @provider.options[:api_key]
    assert_equal 'text-embedding-3-small', @provider.options[:embedding_model]
    assert_equal 'gpt-3.5-turbo', @provider.options[:chat_model]
    assert_equal 30, @provider.options[:timeout]
  end

  def test_initialize_validates_required_options
    assert_raises(Prescient::Error) do
      Prescient::Provider::OpenAI.new(embedding_model: 'test')
    end

    assert_raises(Prescient::Error) do
      Prescient::Provider::OpenAI.new(api_key: 'test')
    end
  end

  def test_embedding_dimensions_constant
    assert_equal 1536, Prescient::Provider::OpenAI::EMBEDDING_DIMENSIONS['text-embedding-3-small']
    assert_equal 3072, Prescient::Provider::OpenAI::EMBEDDING_DIMENSIONS['text-embedding-3-large']
    assert_equal 1536, Prescient::Provider::OpenAI::EMBEDDING_DIMENSIONS['text-embedding-ada-002']
  end

  def test_generate_embedding_success
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'data' => [
        { 'embedding' => Array.new(1536) { |i| i * 0.001 } },
      ],
    })

    @provider.class.expects(:post).with(
      '/v1/embeddings',
      has_entries(
        headers: {
          'Content-Type'  => 'application/json',
          'Authorization' => 'Bearer test-api-key',
        },
        body:    regexp_matches(/text-embedding-3-small/),
      ),
    ).returns(mock_response)

    result = @provider.generate_embedding('test text')

    assert_equal 1536, result.length
    assert_instance_of Float, result.first
  end

  def test_generate_embedding_normalizes_dimensions
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'data' => [
        { 'embedding' => [0.1, 0.2, 0.3] }, # Too few dimensions
      ],
    })

    @provider.class.expects(:post).returns(mock_response)

    result = @provider.generate_embedding('test text')

    # Should be normalized to 1536 dimensions
    assert_equal 1536, result.length
    assert_equal [0.1, 0.2, 0.3] + Array.new(1533, 0.0), result
  end

  def test_generate_embedding_handles_missing_data
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({ 'data' => [] })

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::InvalidResponseError) do
      @provider.generate_embedding('test text')
    end
  end

  def test_generate_embedding_handles_http_errors
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(false)
    mock_response.stubs(:code).returns(401)
    mock_response.stubs(:message).returns('Unauthorized')

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::AuthenticationError) do
      @provider.generate_embedding('test text')
    end
  end

  def test_generate_response_success
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'choices' => [
        {
          'message'       => { 'content' => 'This is a test response' },
          'finish_reason' => 'stop',
        },
      ],
      'usage'   => {
        'prompt_tokens'     => 10,
        'completion_tokens' => 5,
        'total_tokens'      => 15,
      },
    })

    @provider.class.expects(:post).with(
      '/v1/chat/completions',
      has_entries(
        headers: {
          'Content-Type'  => 'application/json',
          'Authorization' => 'Bearer test-api-key',
        },
      ),
    ).returns(mock_response)

    result = @provider.generate_response('test prompt')

    assert_equal 'This is a test response', result[:response]
    assert_equal 'gpt-3.5-turbo', result[:model]
    assert_equal 'openai', result[:provider]
    assert_equal 'stop', result[:metadata][:finish_reason]
    assert_equal 15, result[:metadata][:usage]['total_tokens']
  end

  def test_generate_response_with_context_items
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'choices' => [{ 'message' => { 'content' => 'Response with context' } }],
    })

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
    mock_response.stubs(:parsed_response).returns({
      'choices' => [{ 'message' => { 'content' => 'Custom response' } }],
    })

    @provider.class.expects(:post).with(
      '/v1/chat/completions',
      has_entries(
        body: regexp_matches(/1000.*0\.8.*0\.95/),
      ),
    ).returns(mock_response)

    @provider.generate_response('test', [], max_tokens: 1000, temperature: 0.8, top_p: 0.95)
  end

  def test_generate_response_handles_missing_content
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({ 'choices' => [] })

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::InvalidResponseError) do
      @provider.generate_response('test prompt')
    end
  end

  def test_health_check_success
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'data' => [
        { 'id' => 'text-embedding-3-small', 'object' => 'model' },
        { 'id' => 'gpt-3.5-turbo', 'object' => 'model' },
      ],
    })

    @provider.class.expects(:get).with(
      '/v1/models',
      has_entries(
        headers: { 'Authorization' => 'Bearer test-api-key' },
      ),
    ).returns(mock_response)

    result = @provider.health_check

    assert_equal 'healthy', result[:status]
    assert_equal 'openai', result[:provider]
    assert_includes result[:models_available], 'text-embedding-3-small'
    assert_includes result[:models_available], 'gpt-3.5-turbo'
    assert result[:embedding_model][:available]
    assert result[:chat_model][:available]
    assert result[:ready]
  end

  def test_health_check_with_missing_models
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'data' => [
        { 'id' => 'text-embedding-3-small', 'object' => 'model' },
        # Missing gpt-3.5-turbo
      ],
    })

    @provider.class.expects(:get).returns(mock_response)

    result = @provider.health_check

    assert_equal 'healthy', result[:status]
    assert result[:embedding_model][:available]
    refute result[:chat_model][:available]
    refute result[:ready]
  end

  def test_health_check_handles_errors
    @provider.class.expects(:get).raises(StandardError.new('Connection failed'))

    result = @provider.health_check

    assert_equal 'unavailable', result[:status]
    assert_equal 'openai', result[:provider]
    assert_equal 'Prescient::Error', result[:error]
    assert_equal 'Unexpected error: Connection failed', result[:message]
  end

  def test_list_models_success
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'data' => [
        {
          'id'       => 'gpt-3.5-turbo',
          'created'  => 1_677_610_602,
          'owned_by' => 'openai',
        },
        {
          'id'       => 'text-embedding-3-small',
          'created'  => 1_677_649_963,
          'owned_by' => 'openai',
        },
      ],
    })

    @provider.class.expects(:get).returns(mock_response)

    result = @provider.list_models

    assert_equal 2, result.length
    assert_equal 'gpt-3.5-turbo', result.first[:name]
    assert_equal 1_677_610_602, result.first[:created]
    assert_equal 'openai', result.first[:owned_by]
  end

  def test_error_handling_for_different_status_codes
    # Test rate limiting
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(false)
    mock_response.stubs(:code).returns(429)
    mock_response.stubs(:body).returns('Rate limit exceeded')

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::RateLimitError) do
      @provider.generate_embedding('test')
    end

    # Test bad request
    mock_response.stubs(:code).returns(400)
    mock_response.stubs(:body).returns('Bad request')

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
    # Test that text is properly cleaned before sending to API
    @provider.class.expects(:post).with(
      anything,
      has_entries(
        body: regexp_matches(/"input":"test text"/),
      ),
    ).returns(stub(success?: true, parsed_response: { 'data' => [{ 'embedding' => [0.1] }] }))

    @provider.generate_embedding("  test   text  \n")
  end
end
