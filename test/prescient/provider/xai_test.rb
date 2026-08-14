# frozen_string_literal: true

require 'test_helper'

class XAIProviderTest < PrescientTest
  def setup
    super
    @provider = Prescient::Provider::XAI.new(
      api_key:    'test-api-key',
      chat_model: 'grok-4.5',
      timeout:    30,
    )
  end

  def test_initialize_sets_configuration
    assert_equal 'test-api-key', @provider.options[:api_key]
    assert_equal 'grok-4.5', @provider.options[:chat_model]
    assert_equal 30, @provider.options[:timeout]
  end

  def test_initialize_validates_required_options
    assert_raises(Prescient::Error) do
      Prescient::Provider::XAI.new(chat_model: 'chat')
    end

    assert_raises(Prescient::Error) do
      Prescient::Provider::XAI.new(api_key: 'test')
    end
  end

  def test_generate_embedding_reports_unsupported_capability
    error = assert_raises(Prescient::Error) { @provider.generate_embedding('test') }

    assert_includes error.message, 'does not support embeddings'
  end

  def test_generate_response_success
    response = stub(
      success?:        true,
      parsed_response: {
        'choices' => [{
          'message'       => { 'content' => 'Hello from xAI' },
          'finish_reason' => 'stop',
        }],
        'usage'   => { 'total_tokens' => 12 },
      },
    )
    @provider.class.expects(:post).with(
      '/v1/chat/completions',
      has_entries(
        headers: {
          'Content-Type'  => 'application/json',
          'Authorization' => 'Bearer test-api-key',
        },
        body:    regexp_matches(/grok-4\.5/),
      ),
    ).returns(response)

    result = @provider.generate_response('test prompt')

    assert_equal 'Hello from xAI', result[:response]
    assert_equal 'grok-4.5', result[:model]
    assert_equal 'xai', result[:provider]
    assert_equal 'stop', result[:metadata][:finish_reason]
  end

  def test_generate_response_supports_context_and_options
    response = stub(
      success?:        true,
      parsed_response: { 'choices' => [{ 'message' => { 'content' => 'answer' } }] },
    )
    @provider.class.expects(:post).with(
      '/v1/chat/completions',
      has_entries(body: regexp_matches(/1000.*0\.8.*0\.95/)),
    ).returns(response)

    result = @provider.generate_response(
      'test', [{ 'title' => 'Document', 'content' => 'Context' }],
      max_tokens: 1000, temperature: 0.8, top_p: 0.95
    )

    assert_equal 'answer', result[:response]
  end

  def test_generate_response_rejects_missing_content
    response = stub(success?: true, parsed_response: { 'choices' => [] })
    @provider.class.expects(:post).returns(response)

    assert_raises(Prescient::InvalidResponseError) { @provider.generate_response('test') }
  end

  def test_health_check_success_and_missing_model
    response = stub(
      success?:        true,
      parsed_response: { 'data' => [{ 'id' => 'grok-4.5' }] },
    )
    @provider.class.expects(:get).with(
      '/v1/models',
      has_entries(
        headers: {
          'Content-Type'  => 'application/json',
          'Authorization' => 'Bearer test-api-key',
        },
      ),
    ).returns(response)

    result = @provider.health_check

    assert_equal 'healthy', result[:status]
    assert result[:chat_model][:available]
    assert result[:ready]

    missing_response = stub(success?: true, parsed_response: { 'data' => [{ 'id' => 'other-model' }] })
    @provider.class.expects(:get).returns(missing_response)
    result = @provider.health_check

    refute result[:chat_model][:available]
    refute result[:ready]
  end

  def test_health_check_reports_http_and_connection_failures
    response = stub(success?: false, code: 401, message: 'Unauthorized')
    @provider.class.expects(:get).returns(response)

    result = @provider.health_check

    assert_equal 'unhealthy', result[:status]
    assert_equal 'HTTP 401', result[:error]

    @provider.class.expects(:get).raises(StandardError.new('Connection failed'))
    result = @provider.health_check

    assert_equal 'unavailable', result[:status]
  end

  def test_list_models
    response = stub(
      success?:        true,
      parsed_response: {
        'data' => [{
          'id'             => 'grok-4.5',
          'object'         => 'model',
          'created'        => 1_700_000_000,
          'owned_by'       => 'xai',
          'context_length' => 256_000,
        }],
      },
    )
    @provider.class.expects(:get).returns(response)

    result = @provider.list_models

    assert_equal 'grok-4.5', result.first[:name]
    assert_equal 'xai', result.first[:owned_by]
  end
end
