# frozen_string_literal: true

require 'test_helper'

class APITest < PrescientTest
  class APIProvider < Prescient::Base
    class << self
      attr_accessor :last_request
    end

    def generate_embedding(text, **options)
      self.class.last_request = { operation: :embedding, text: text, options: options }
      [0.1, 0.2, 0.3]
    end

    def generate_response(prompt, context_items = [], **options)
      self.class.last_request = { operation: :generate, prompt: prompt, context: context_items, options: options }
      { response: 'generated', model: options[:model] || 'test-model', provider: 'api-test' }
    end

    def health_check
      { status: 'healthy', provider: 'api-test', reachable: true, ready: true }
    end

    def list_models
      [{ name: 'test-model', type: 'text' }]
    end

    protected

    def validate_configuration!
      # No validation needed for this test provider.
    end
  end

  class AvailableModelsProvider < APIProvider
    undef_method :list_models

    def available_models
      [{ name: 'local-model', embedding: true, chat: true }]
    end
  end

  class BareProvider < Prescient::Base
    def generate_embedding(_text, **_options)
      [0.1]
    end

    def generate_response(_prompt, _context = [], **_options)
      { response: 'bare', provider: 'bare' }
    end

    def health_check
      { status: 'healthy', provider: 'bare', reachable: true, ready: true }
    end

    protected

    def validate_configuration!
      # No validation needed for this test provider.
    end
  end

  class APISearchTool < Prescient::Tool::Base
    class << self
      attr_accessor :last_request
    end

    def search(query, limit: nil)
      self.class.last_request = { query: query, limit: limit }
      {
        tool:    'web_search',
        query:   query,
        source:  'test',
        results: [{ title: 'Ruby', url: 'https://www.ruby-lang.org', snippet: 'Ruby' }],
      }
    end
  end

  class FailureProvider < APIProvider
    def generate_response(*_args, **_options)
      failure = @options.fetch(:failure)
      raise StandardError, 'unexpected failure' if failure == 'StandardError'

      raise Prescient.const_get(failure)
    end
  end

  class HealthFailureProvider < APIProvider
    def health_check
      raise Prescient::Error, 'health unavailable'
    end
  end

  class UnreadyProvider < APIProvider
    def health_check
      { status: 'healthy', provider: 'unready', reachable: true, ready: false }
    end
  end

  def setup
    super
    APIProvider.last_request = nil
    APISearchTool.last_request = nil
    Prescient.configure do |config|
      config.default_provider = :api_test
      config.add_provider(:api_test, APIProvider)
      config.add_tool(:web_search, APISearchTool)
    end
    @api = Prescient::API.new
  end

  def test_health_version_provider_model_and_capability_endpoints
    assert_equal 200, call('GET', '/healthz').first
    assert_equal 'ok', body(call('GET', '/healthz'))['status']
    assert_equal 200, call('GET', '/readyz').first
    assert_equal 'ready', body(call('GET', '/readyz'))['status']

    version = body(call('GET', '/v1/version'))

    assert_equal Prescient::VERSION, version['version']
    assert_equal '1', version['api_version']

    assert_equal(['api_test'], body(call('GET', '/v1/providers'))['providers'].map { |item| item['name'] })
    assert_equal 'test-model', body(call('GET', '/v1/models'))['models'].first['model']['name']
    assert body(call('GET', '/v1/capabilities'))['capabilities'].first['generation']
    assert_equal 'healthy', body(call('GET', '/v1/health?provider=api_test'))['status']
  end

  def test_models_capabilities_and_health_aggregate_all_provider_shapes
    Prescient.configuration.add_provider(:available, AvailableModelsProvider)
    Prescient.configuration.add_provider(:bare, BareProvider)

    models = body(call('GET', '/v1/models?provider=available'))['models']

    assert_equal 'local-model', models.first['model']['name']
    assert_empty body(call('GET', '/v1/models?provider=bare'))['models']

    capabilities = body(call('GET', '/v1/capabilities'))['capabilities']

    assert_equal 3, capabilities.length
    assert(capabilities.any? { |item| item['model_listing'] == false })

    health = body(call('GET', '/v1/health'))

    assert_equal 'healthy', health['api_test']['status']
  end

  def test_generate_embedding_and_batch_endpoints_use_client_contract
    result = body(call('POST', '/v1/generate', body: {
      prompt:      'hello',
      context:     [{ 'title' => 'context' }],
      provider:    'api_test',
      model:       'override-model',
      temperature: 0.2,
      max_tokens:  20,
      top_p:       0.8,
    }))

    assert_equal 'generated', result['response']
    assert_equal 'hello', APIProvider.last_request[:prompt]
    assert_equal 'override-model', APIProvider.last_request[:options][:model]

    result = body(call('POST', '/v1/generate', body: {
      prompt:    'summarize',
      documents: [{ 'title' => 'Ruby' }],
      provider:  'api_test',
    }))

    assert_equal 'generated', result['response']
    assert_equal 'Ruby', APIProvider.last_request[:context].first['title']

    embedding = body(call('POST', '/v1/embeddings', body: { input: 'hello', provider: 'api_test' }))

    assert_equal [0.1, 0.2, 0.3], embedding['embedding']
    assert_equal 'api_test', embedding['provider']

    batch = body(call('POST', '/v1/embeddings/batch', body: { inputs: ['one', 'two'], provider: 'api_test' }))

    assert_equal 2, batch['embeddings'].length
    assert_equal 3, batch['dimensions']
  end

  def test_search_generate_endpoint_feeds_tool_results_to_provider
    result = body(call('POST', '/v1/search/generate', body: {
      query:    'Ruby tools',
      tool:     'web_search',
      provider: 'api_test',
      limit:    3,
      model:    'search-model',
      fallback: false,
    }))

    assert_equal 'generated', result['response']
    assert_equal({ query: 'Ruby tools', limit: 3 }, APISearchTool.last_request)
    assert_equal 'Ruby tools', APIProvider.last_request[:prompt]
    assert_equal 'Ruby', APIProvider.last_request[:context].first[:title]
    assert_equal 'search-model', APIProvider.last_request[:options][:model]
  end

  def test_agent_endpoint_runs_bounded_task_and_passes_request_context
    authorization = ->(tool:, context:, **) {
      tool == :accounts && context[:tenant_id] == 'tenant-1'
    }
    @api = Prescient::API.new(authorization:)
    result = body(call('POST', '/v1/agent', body: {
      prompt: 'summarize accounts', provider: 'api_test', tools: [], max_loops: 2
    }, headers: { 'HTTP_X_TENANT_ID' => 'tenant-1' }))

    assert_equal 'generated', result['response']
    assert_equal [], result['metadata']['actions']
  end

  def test_agent_endpoint_rejects_invalid_tool_lists
    response = call('POST', '/v1/agent', body: { prompt: 'task', tools: 'search' })

    assert_equal 400, response.first
    assert_equal 'invalid_request', body(response).dig('error', 'type')

    @api = Prescient::API.new(request_context: ->(_env) { Object.new })
    invalid_context = call('POST', '/v1/agent', body: { prompt: 'task' })

    assert_equal 400, invalid_context.first
  end

  def test_search_endpoint_returns_normalized_tool_results_without_generation
    result = body(call('POST', '/v1/search', body: {
      query: 'Ruby tools',
      limit: 3,
    }))

    assert_equal 'web_search', result['tool']
    assert_equal 'Ruby tools', result['query']
    assert_equal 'test', result['source']
    assert_equal 'Ruby', result['results'].first['title']
    assert_equal({ query: 'Ruby tools', limit: 3 }, APISearchTool.last_request)
    assert_nil APIProvider.last_request
  end

  def test_search_generate_uses_the_configured_default_provider
    result = body(call('POST', '/v1/search/generate', body: { query: 'Ruby tools' }))

    assert_equal 'generated', result['response']
    assert_equal 'Ruby tools', APIProvider.last_request[:prompt]
  end

  def test_request_ids_authentication_and_error_envelopes
    response = call('GET', '/v1/providers', headers: { 'HTTP_X_REQUEST_ID' => 'request-123' })

    assert_equal 'request-123', response[1]['x-request-id']
    assert_equal 'request-123', body(response)['request_id']

    protected_api = Prescient::API.new(authentication: ->(_env) { false })
    unauthorized = protected_api.call('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/v1/providers')

    assert_equal 401, unauthorized.first
    assert_equal 'authentication_required', body(unauthorized).dig('error', 'type')
    assert_equal 200, protected_api.call('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/healthz').first

    generated_id = call('GET', '/v1/providers', headers: { 'HTTP_X_REQUEST_ID' => 'not valid' })

    assert_match(/\A[0-9a-f-]{36}\z/, generated_id[1]['x-request-id'])

    invalid = call('POST', '/v1/generate', body: { context: [] })

    assert_equal 400, invalid.first
    assert_equal 'invalid_request', body(invalid).dig('error', 'type')

    missing_route = call('GET', '/v1/unknown')

    assert_equal 404, missing_route.first
    assert_equal 'not_found', body(missing_route).dig('error', 'type')
  end

  def test_request_limits_and_batch_limits
    limited_api = Prescient::API.new(max_body_bytes: 10)
    oversized = limited_api.call(
      'REQUEST_METHOD' => 'POST',
      'PATH_INFO'      => '/v1/embeddings',
      'CONTENT_LENGTH' => '100',
      'rack.input'     => StringIO.new('{}'),
    )

    assert_equal 400, oversized.first
    assert_includes body(oversized).dig('error', 'message'), 'exceeds'

    too_many = call('POST', '/v1/embeddings/batch', body: { inputs: Array.new(33, 'text'), provider: 'api_test' })

    assert_equal 400, too_many.first
    assert_includes body(too_many).dig('error', 'message'), 'more than'
  end

  def test_request_body_parsing_and_validation
    limited_api = Prescient::API.new(max_body_bytes: 10)
    invalid_json = @api.call(
      'REQUEST_METHOD' => 'POST',
      'PATH_INFO'      => '/v1/embeddings',
      'rack.input'     => StringIO.new('{'),
    )

    assert_equal 400, invalid_json.first
    assert_equal 'invalid_json', body(invalid_json).dig('error', 'type')

    body_oversized = call_raw_with_api(limited_api, 'POST', '/v1/embeddings', JSON.generate(input: 'too long'))

    assert_equal 400, body_oversized.first

    non_object = call_raw('POST', '/v1/embeddings', '[]')

    assert_equal 400, non_object.first
    assert_includes body(non_object).dig('error', 'message'), 'JSON object'

    valid_without_content_length = call_raw('POST', '/v1/embeddings', JSON.generate(input: 'text'))

    assert_equal 200, valid_without_content_length.first
    assert_raises(ArgumentError) { Prescient::API.new(max_body_bytes: 0) }
  end

  def test_readiness_reports_unready_and_unavailable_providers
    Prescient.reset_configuration!
    Prescient.configure do |config|
      config.default_provider = :unready
      config.add_provider(:unready, UnreadyProvider)
      config.add_provider(:unavailable, HealthFailureProvider)
    end
    @api = Prescient::API.new

    response = call('GET', '/readyz')

    assert_equal 503, response.first
    assert_equal 'not_ready', body(response)['status']
  end

  def test_response_without_request_id_omits_request_header
    response = @api.send(:response, 204, { status: 'empty' })

    refute response[1].key?('x-request-id')
  end

  def test_request_validation_and_error_status_mapping
    assert_equal 400, call('POST', '/v1/generate', body: { prompt: '', provider: 'api_test' }).first
    assert_equal 400, call('POST', '/v1/generate', body: { prompt: 'hello', context: {} }).first
    assert_equal 400, call('POST', '/v1/generate', body: { prompt: 'hello', fallback: 'yes' }).first
    assert_equal 400, call('POST', '/v1/embeddings', body: { input: '' }).first
    assert_equal 400, call('POST', '/v1/embeddings/batch', body: { inputs: [] }).first
    assert_equal 400, call('POST', '/v1/embeddings/batch', body: { inputs: [1] }).first
    assert_equal 404, call('PATCH', '/v1/providers').first
    assert_equal 500, call('GET', '/v1/models?provider=missing').first

    expected_statuses = {
      'AuthenticationError'    => 401,
      'RateLimitError'         => 429,
      'ConnectionError'        => 503,
      'ProviderError'          => 503,
      'ModelNotAvailableError' => 422,
    }
    expected_statuses.each do |failure, expected_status|
      Prescient.configuration.add_provider(:failure, FailureProvider, failure: failure)

      assert_equal expected_status,
                   call('POST', '/v1/generate', body: { provider: 'failure', prompt: 'hello', fallback: false }).first
    end

    Prescient.configuration.add_provider(:failure, FailureProvider, failure: 'StandardError')

    assert_equal 500, call('POST', '/v1/generate', body: { provider: 'failure', prompt: 'hello', fallback: false }).first
  end

  def test_search_generate_request_validation
    assert_equal 400, call('POST', '/v1/search/generate', body: { query: 'hello', limit: 0 }).first
    assert_equal 400, call('POST', '/v1/search/generate', body: { query: 'hello', fallback: 'yes' }).first
    assert_equal 400, call('POST', '/v1/search', body: { query: 'hello', tool: 1 }).first

    missing_tool = call('POST', '/v1/search', body: { query: 'hello', tool: 'missing' })

    assert_equal 500, missing_tool.first
    assert_equal 'toolconfiguration', body(missing_tool).dig('error', 'type')
  end

  private

  def call(method, path, body: nil, headers: {})
    env = {
      'REQUEST_METHOD' => method,
      'REQUEST_URI'    => path,
      'rack.input'     => StringIO.new(body ? JSON.generate(body) : ''),
    }.merge(headers)
    @api.call(env)
  end

  def call_raw(method, path, body)
    @api.call(
      'REQUEST_METHOD' => method,
      'PATH_INFO'      => path,
      'rack.input'     => StringIO.new(body),
    )
  end

  def call_raw_with_api(api, method, path, body)
    api.call(
      'REQUEST_METHOD' => method,
      'PATH_INFO'      => path,
      'rack.input'     => StringIO.new(body),
    )
  end

  def body(response)
    JSON.parse(response[2].join)
  end
end
