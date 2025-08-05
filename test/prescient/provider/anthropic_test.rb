# frozen_string_literal: true

require 'test_helper'

class AnthropicProviderTest < PrescientTest
  def setup
    super
    @provider = Prescient::Provider::Anthropic.new(
      api_key: 'test-api-key',
      model:   'claude-3-haiku-20240307',
      timeout: 30,
    )
  end

  def test_initialize_sets_configuration
    assert_equal 'test-api-key', @provider.options[:api_key]
    assert_equal 'claude-3-haiku-20240307', @provider.options[:model]
    assert_equal 30, @provider.options[:timeout]
  end

  def test_initialize_validates_required_options
    assert_raises(Prescient::Error) do
      Prescient::Provider::Anthropic.new(model: 'test')
    end

    assert_raises(Prescient::Error) do
      Prescient::Provider::Anthropic.new(api_key: 'test')
    end
  end

  def test_generate_embedding_raises_not_supported_error
    assert_raises(Prescient::Error) do
      @provider.generate_embedding('test text')
    end

    error = assert_raises(Prescient::Error) {
      @provider.generate_embedding('test text')
    }

    assert_includes error.message, 'does not support embeddings'
    assert_includes error.message, 'OpenAI or HuggingFace'
  end

  def test_generate_response_success
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'content' => [
        { 'text' => 'This is a test response from Claude' },
      ],
      'usage'   => {
        'input_tokens'  => 10,
        'output_tokens' => 8,
      },
    })

    @provider.class.expects(:post).with(
      '/v1/messages',
      has_entries(
        headers: {
          'Content-Type'      => 'application/json',
          'x-api-key'         => 'test-api-key',
          'anthropic-version' => '2023-06-01',
        },
      ),
    ).returns(mock_response)

    result = @provider.generate_response('test prompt')

    assert_equal 'This is a test response from Claude', result[:response]
    assert_equal 'claude-3-haiku-20240307', result[:model]
    assert_equal 'anthropic', result[:provider]
    assert_nil result[:processing_time]
    assert_equal 10, result[:metadata][:usage]['input_tokens']
    assert_equal 8, result[:metadata][:usage]['output_tokens']
  end

  def test_generate_response_with_context_items
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'content' => [{ 'text' => 'Response with context' }],
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
      'content' => [{ 'text' => 'Custom response' }],
    })

    @provider.class.expects(:post).with(
      '/v1/messages',
      has_entries(
        body: regexp_matches(/1000.*0\.8/),
      ),
    ).returns(mock_response)

    @provider.generate_response('test', [], max_tokens: 1000, temperature: 0.8)
  end

  def test_generate_response_handles_missing_content
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({ 'content' => [] })

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::InvalidResponseError) do
      @provider.generate_response('test prompt')
    end
  end

  def test_generate_response_handles_malformed_content
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'content' => [{ 'type' => 'image' }], # No text field
    })

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::InvalidResponseError) do
      @provider.generate_response('test prompt')
    end
  end

  def test_health_check_success
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'content' => [{ 'text' => 'Hello' }],
    })

    @provider.class.expects(:post).with(
      '/v1/messages',
      has_entries(
        headers: {
          'Content-Type'      => 'application/json',
          'x-api-key'         => 'test-api-key',
          'anthropic-version' => '2023-06-01',
        },
        body:    regexp_matches(/"max_tokens":10.*"content":"Test"/),
      ),
    ).returns(mock_response)

    result = @provider.health_check

    assert_equal 'healthy', result[:status]
    assert_equal 'anthropic', result[:provider]
    assert_equal 'claude-3-haiku-20240307', result[:model]
    assert result[:ready]
  end

  def test_health_check_handles_http_failure
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(false)
    mock_response.stubs(:code).returns(401)
    mock_response.stubs(:message).returns('Unauthorized')

    @provider.class.expects(:post).returns(mock_response)

    result = @provider.health_check

    assert_equal 'unhealthy', result[:status]
    assert_equal 'anthropic', result[:provider]
    assert_equal 'HTTP 401', result[:error]
    assert_equal 'Unauthorized', result[:message]
  end

  def test_health_check_handles_connection_errors
    @provider.class.expects(:post).raises(Prescient::ConnectionError.new('Connection failed'))

    result = @provider.health_check

    assert_equal 'unavailable', result[:status]
    assert_equal 'anthropic', result[:provider]
    assert_equal 'Prescient::ConnectionError', result[:error]
    assert_equal 'Connection failed', result[:message]
  end

  def test_list_models
    # Anthropic doesn't provide a models API, so it returns static list
    result = @provider.list_models

    assert_instance_of Array, result
    assert_operator result.length, :>=, 3

    haiku_model = result.find { |m| m[:name] == 'claude-3-haiku-20240307' }

    assert haiku_model
    assert_equal 'text', haiku_model[:type]

    sonnet_model = result.find { |m| m[:name] == 'claude-3-sonnet-20240229' }

    assert sonnet_model
    assert_equal 'text', sonnet_model[:type]

    opus_model = result.find { |m| m[:name] == 'claude-3-opus-20240229' }

    assert opus_model
    assert_equal 'text', opus_model[:type]
  end

  def test_error_handling_for_different_status_codes
    # Test bad request
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(false)
    mock_response.stubs(:code).returns(400)
    mock_response.stubs(:body).returns('Bad request')

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::Error) do
      @provider.generate_response('test')
    end

    # Test authentication error
    mock_response.stubs(:code).returns(401)
    mock_response.stubs(:body).returns('Authentication failed')

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::AuthenticationError) do
      @provider.generate_response('test')
    end

    # Test forbidden
    mock_response.stubs(:code).returns(403)
    mock_response.stubs(:body).returns('Forbidden')

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::AuthenticationError) do
      @provider.generate_response('test')
    end

    # Test rate limiting
    mock_response.stubs(:code).returns(429)
    mock_response.stubs(:body).returns('Rate limit exceeded')

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::RateLimitError) do
      @provider.generate_response('test')
    end

    # Test server error
    mock_response.stubs(:code).returns(500)
    mock_response.stubs(:body).returns('Internal server error')

    @provider.class.expects(:post).returns(mock_response)

    assert_raises(Prescient::Error) do
      @provider.generate_response('test')
    end
  end

  def test_request_structure
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'content' => [{ 'text' => 'Response' }],
    })

    # Verify the request structure matches Anthropic's API requirements
    @provider.class.expects(:post).with(
      '/v1/messages',
      has_entries(
        headers: {
          'Content-Type'      => 'application/json',
          'x-api-key'         => 'test-api-key',
          'anthropic-version' => '2023-06-01',
        },
        body:    regexp_matches(/"model":"claude-3-haiku-20240307".*"messages":\[\{"role":"user"/),
      ),
    ).returns(mock_response)

    @provider.generate_response('test prompt')
  end

  def test_build_prompt_integration
    # Test that build_prompt is called and formats correctly
    mock_response = mock('response')
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      'content' => [{ 'text' => 'Response' }],
    })

    context_items = [{ 'title' => 'Doc', 'content' => 'Content' }]

    @provider.class.expects(:post).with(
      anything,
      has_entries(
        body: regexp_matches(/1\. title: Doc, content: Content/),
      ),
    ).returns(mock_response)

    @provider.generate_response('test', context_items)
  end
end
