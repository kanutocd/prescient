# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'stringio'
require 'uri'
require_relative '../prescient'

# Dependency-free Rack-compatible HTTP application for Prescient operations.
#
# The application exposes only generic Prescient operations. It does not
# expose provider-specific methods, credentials, or raw provider responses.
class Prescient::API
  # @return [Integer] Default maximum request body size in bytes
  DEFAULT_MAX_BODY_BYTES = 1_048_576
  # @return [Integer] Maximum number of inputs accepted by batch embeddings
  MAX_BATCH_SIZE = 32
  # @return [String] HTTP API version
  API_VERSION = '1'
  # @return [Hash<Array<String>, Symbol>] Generic HTTP route handlers
  ROUTES = {
    ['GET',  '/healthz']             => :healthz_response,
    ['GET',  '/readyz']              => :readiness_response,
    ['GET',  '/v1/version']          => :version_response,
    ['GET',  '/v1/providers']        => :providers_response,
    ['GET',  '/v1/models']           => :models_response,
    ['GET',  '/v1/capabilities']     => :capabilities_response,
    ['GET',  '/v1/health']           => :health_response,
    ['POST', '/v1/generate']         => :generate_response,
    ['POST', '/v1/search']           => :search_response,
    ['POST', '/v1/search/generate']  => :search_generate_response,
    ['POST', '/v1/agent']            => :agent_response,
    ['POST', '/v1/embeddings']       => :embeddings_response,
    ['POST', '/v1/embeddings/batch'] => :batch_embeddings_response,
  }.freeze

  # @param authentication [#call, nil] Optional authentication hook
  # @param max_body_bytes [Integer] Maximum accepted request body size
  # @return [void]
  def initialize(authentication: nil, authorization: nil, request_context: nil,
                 max_body_bytes: DEFAULT_MAX_BODY_BYTES)
    @authentication = authentication
    @authorization = authorization
    @request_context = request_context
    @max_body_bytes = validate_body_limit(max_body_bytes)
  end

  # Handle a Rack-style environment and return a Rack response tuple.
  # @param env [Hash] Rack-compatible request environment
  # @return [Array(Integer, Hash, Array<String>)] HTTP status, headers, body
  def call(env)
    request_id = request_id_for(env)
    public_path = request_target(env).first
    return dispatch(env, request_id) if ['/healthz', '/readyz'].include?(public_path)

    unless authenticated?(env)
      return response(401,
                      error_payload('authentication_required', 'authentication required',
                                    request_id))
    end

    dispatch(env, request_id)
  rescue StandardError => e
    handle_exception(e, request_id)
  end

  private

  def dispatch(env, request_id)
    method = env.fetch('REQUEST_METHOD', 'GET').upcase
    path, query = request_target(env)
    handler = ROUTES[[method, path]]
    return response(404, error_payload('not_found', 'route not found', request_id)) unless handler

    send(handler, env, query, request_id)
  end

  def healthz_response(_env, _query, request_id)
    json_response(200, { status: 'ok' }, request_id)
  end

  def version_response(_env, _query, request_id)
    json_response(200, { version: Prescient::VERSION, api_version: API_VERSION }, request_id)
  end

  def generate_response(env, _query, request_id)
    payload = request_payload(env)
    prompt = required_string(payload, 'prompt')
    context = if payload.key?('documents')
                Prescient::DocumentSource::Memory.new(documents: payload['documents']).fetch
              else
                payload.fetch('context', [])
              end
    raise ArgumentError, 'context must be an array' unless context.is_a?(Array)

    client = client_for(payload)
    result = client.generate_response(prompt, context, **generation_options(payload))
    json_response(200, result, request_id)
  end

  def search_generate_response(env, _query, request_id)
    payload = request_payload(env)
    query = required_string(payload, 'query')
    tool = search_tool_name(payload)
    fallback = search_fallback(payload)
    limit = search_limit(payload)

    result = Prescient.search_and_generate(
      query,
      tool:            tool,
      provider:        payload['provider']&.to_sym,
      limit:           limit,
      enable_fallback: fallback,
      **generation_options(payload),
    )
    json_response(200, result, request_id)
  end

  def search_response(env, _query, request_id)
    payload = request_payload(env)
    query = required_string(payload, 'query')
    tool_name = search_tool_name(payload)
    tool = Prescient.tool(tool_name)
    raise Prescient::ToolConfigurationError, "tool not configured: #{tool_name}" unless tool

    result = tool.search(query, limit: search_limit(payload))
    json_response(200, result, request_id)
  end

  def agent_response(env, _query, request_id)
    require 'prescient/agent'
    payload = request_payload(env)
    prompt = required_string(payload, 'prompt')
    json_response(200, agent_runtime(payload, env, request_id).run(prompt).to_h, request_id)
  end

  def agent_runtime(payload, env, request_id)
    tools = payload.fetch('tools', [])
    validate_agent_tools(tools)
    configuration = Prescient::Agent::Configuration.new(max_loops: payload.fetch('max_loops', 5))
    Prescient::Agent::Runtime.new(
      provider:           payload['provider']&.to_sym,
      client:             client_for(payload),
      tool_names:         tools,
      configuration:      configuration,
      authorization:      @authorization,
      generation_options: model_options(payload),
      request_context:    request_context(env, request_id),
    )
  end

  def validate_agent_tools(tools)
    valid = tools.is_a?(Array) && tools.all? { |name| name.is_a?(String) && !name.empty? }
    raise ArgumentError, 'tools must be an array of names' unless valid
  end

  def search_tool_name(payload)
    value = payload.fetch('tool', 'web_search')
    raise ArgumentError, 'tool must be a non-empty string' unless value.is_a?(String) && !value.empty?

    value.to_sym
  end

  def search_fallback(payload)
    fallback = payload.key?('fallback') ? payload['fallback'] : true
    raise ArgumentError, 'fallback must be boolean' unless [true, false].include?(fallback)

    fallback
  end

  def search_limit(payload)
    limit = payload['limit']
    raise ArgumentError, 'limit must be a positive integer' if limit && (!limit.is_a?(Integer) || !limit.positive?)

    limit
  end

  def embeddings_response(env, _query, request_id)
    payload = request_payload(env)
    input = required_string(payload, 'input')
    client = client_for(payload)
    result = client.generate_embedding(input, **model_options(payload))
    json_response(200, embedding_payload(result, client), request_id)
  end

  def batch_embeddings_response(env, _query, request_id)
    payload = request_payload(env)
    inputs = payload['inputs']
    raise ArgumentError, 'inputs must be a non-empty array' unless inputs.is_a?(Array) && inputs.any?
    raise ArgumentError, "inputs cannot contain more than #{MAX_BATCH_SIZE} items" if inputs.length > MAX_BATCH_SIZE
    raise ArgumentError, 'inputs must contain only strings' unless inputs.all?(String)

    client = client_for(payload)
    embeddings = inputs.map { |input| client.generate_embedding(input, **model_options(payload)) }
    result = { embeddings: embeddings, dimensions: embeddings.first.length, provider: client.provider_name.to_s }
    json_response(200,
                  result, request_id)
  end

  def readiness_response(_env, _query, request_id)
    providers = Prescient.configuration.providers.keys
    ready = providers.any? { |name|
      begin
        Prescient.health_check(provider: name)[:ready] == true
      rescue Prescient::Error
        false
      end
    }
    json_response(ready ? 200 : 503, { status: ready ? 'ready' : 'not_ready' }, request_id)
  end

  def providers_response(_env, _query, request_id)
    providers = Prescient.configuration.providers.map { |name, registration|
      { name: name.to_s, class: registration[:class].name }
    }
    json_response(200, { providers: providers }, request_id)
  end

  def models_response(_env, query, request_id)
    names = query['provider'] ? [query['provider'].to_sym] : Prescient.configuration.providers.keys
    models = names.flat_map { |name|
      provider = Prescient.configuration.provider(name)
      raise Prescient::Error, "Provider not configured: #{name}" unless provider

      records = if provider.respond_to?(:list_models)
                  provider.list_models
                elsif provider.respond_to?(:available_models)
                  provider.available_models
                else
                  []
                end
      records.map { |model| { provider: name.to_s, model: model } }
    }
    json_response(200, { models: models }, request_id)
  end

  def capabilities_response(_env, _query, request_id)
    capabilities = Prescient.configuration.providers.map { |name, registration|
      provider = registration[:class]
      {
        provider:      name.to_s,
        generation:    provider.method_defined?(:generate_response),
        embeddings:    provider.method_defined?(:generate_embedding),
        health:        provider.method_defined?(:health_check),
        model_listing: provider.method_defined?(:list_models) || provider.method_defined?(:available_models),
      }
    }
    json_response(200, { capabilities: capabilities }, request_id)
  end

  def health_response(_env, query, request_id)
    if query['provider']
      json_response(200, Prescient.health_check(provider: query['provider'].to_sym), request_id)
    else
      results = Prescient.configuration.providers.keys.to_h { |name|
        [name.to_s, Prescient.health_check(provider: name)]
      }
      json_response(200, results, request_id)
    end
  end

  def client_for(payload)
    provider = payload['provider']&.to_sym
    fallback = payload.key?('fallback') ? payload['fallback'] : true
    raise ArgumentError, 'fallback must be boolean' unless [true, false].include?(fallback)

    Prescient.client(provider, enable_fallback: fallback)
  end

  def generation_options(payload)
    options = model_options(payload)
    ['temperature', 'max_tokens', 'top_p'].each do |key|
      options[key.to_sym] = payload[key] if payload.key?(key)
    end
    options
  end

  def model_options(payload)
    payload['model'] ? { model: payload['model'] } : {}
  end

  def embedding_payload(embedding, client)
    { embedding: embedding, dimensions: embedding.length, provider: client.provider_name.to_s }
  end

  def request_payload(env)
    content_length = env['CONTENT_LENGTH'].to_i
    raise ArgumentError, 'request body exceeds configured limit' if content_length > @max_body_bytes

    body = env.fetch('rack.input', StringIO.new).read(@max_body_bytes + 1)
    raise ArgumentError, 'request body exceeds configured limit' if body.bytesize > @max_body_bytes

    parsed = JSON.parse(body)
    raise ArgumentError, 'request body must contain a JSON object' unless parsed.is_a?(Hash)

    parsed
  end

  def required_string(payload, key)
    value = payload[key]
    raise ArgumentError, "#{key} must be a non-empty string" unless value.is_a?(String) && !value.empty?

    value
  end

  def request_target(env)
    target = env['REQUEST_URI'] || env['PATH_INFO'] || '/'
    path, query = target.split('?', 2)
    [path, URI.decode_www_form(query.to_s).to_h]
  end

  def authenticated?(env)
    return true unless @authentication

    @authentication.call(env) == true
  end

  def request_context(env, request_id)
    base = {
      request_id: request_id,
      tenant_id:  env['HTTP_X_TENANT_ID'],
      principal:  env['REMOTE_USER'],
    }.compact
    return base unless @request_context

    resolved = @request_context.call(env)
    raise ArgumentError, 'request context hook must return a mapping' unless resolved.is_a?(Hash)

    base.merge(resolved)
  end

  def request_id_for(env)
    supplied = env['HTTP_X_REQUEST_ID'].to_s
    supplied.match?(/\A[a-zA-Z0-9._:-]{1,128}\z/) ? supplied : SecureRandom.uuid
  end

  def json_response(status, payload, request_id)
    response(status, payload.merge(request_id: request_id))
  end

  def response(status, payload)
    body = JSON.generate(payload)
    headers = {
      'content-type'   => 'application/json',
      'content-length' => body.bytesize.to_s,
    }
    headers['x-request-id'] = payload[:request_id] if payload[:request_id]
    [status, headers, [body]]
  end

  def error_payload(type, message, request_id)
    { error: { type: type, message: message }, request_id: request_id }
  end

  def error_type(error)
    error.class.name.split('::').last.delete_suffix('Error').downcase
  end

  def error_status(error)
    return 401 if error.is_a?(Prescient::AuthenticationError)
    return 429 if error.is_a?(Prescient::RateLimitError)
    return 503 if error.is_a?(Prescient::ConnectionError) || error.is_a?(Prescient::ProviderError)
    return 422 if error.is_a?(Prescient::ModelNotAvailableError)

    500
  end

  def handle_exception(error, request_id)
    case error
    when JSON::ParserError
      response(400, error_payload('invalid_json', 'request body must contain valid JSON', request_id))
    when ArgumentError
      response(400, error_payload('invalid_request', error.message, request_id))
    when Prescient::Error
      response(error_status(error), error_payload(error_type(error), error.message, request_id))
    else
      response(500, error_payload('internal_error', 'internal server error', request_id))
    end
  end

  def validate_body_limit(value)
    return value if value.is_a?(Integer) && value.positive?

    raise ArgumentError, 'max_body_bytes must be a positive integer'
  end
end
