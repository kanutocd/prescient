# frozen_string_literal: true

require 'httparty'

# Anthropic Messages API provider adapter.
class Prescient::Provider::Anthropic < Prescient::Base
  include HTTParty

  base_uri 'https://api.anthropic.com'

  def initialize(**options)
    super
    self.class.default_timeout(@options[:timeout] || 60)
  end

  # Anthropic does not provide embeddings through this adapter.
  #
  # @raise [Prescient::Error] Always, because Anthropic embeddings are not supported
  def generate_embedding(_text, **_options)
    # Anthropic doesn't provide embedding API, raise error
    raise Prescient::Error,
          'Anthropic provider does not support embeddings. Use OpenAI or HuggingFace for embeddings.'
  end

  # Generate a response using Anthropic's Messages API.
  # @param prompt [String] Prompt to send
  # @param context_items [Array<Hash, String>] Optional context items
  # @return [Hash] Normalized response data
  def generate_response(prompt, context_items = [], **options)
    handle_errors do
      formatted_prompt = build_prompt(prompt, context_items)

      response = self.class.post('/v1/messages',
                                 headers: {
                                   'Content-Type'      => 'application/json',
                                   'x-api-key'         => @options[:api_key],
                                   'anthropic-version' => '2023-06-01',
                                 },
                                 body:    {
                                   model:       @options[:model],
                                   max_tokens:  options[:max_tokens] || 2000,
                                   temperature: options[:temperature] || 0.7,
                                   messages:    [
                                     {
                                       role:    'user',
                                       content: formatted_prompt,
                                     },
                                   ],
                                 }.to_json)

      validate_response!(response, 'text generation')

      content = response.parsed_response.dig('content', 0, 'text')
      raise Prescient::InvalidResponseError, 'No response generated' unless content

      {
        response:        content.strip,
        model:           @options[:model],
        provider:        'anthropic',
        processing_time: nil,
        metadata:        {
          usage: response.parsed_response['usage'],
        },
      }
    end
  end

  # Check Anthropic API availability using the non-generating `/v1/models` endpoint.
  #
  # `reachable` indicates the API answered successfully. `ready` indicates that
  # the configured model appears in the returned model list.
  #
  # @return [Hash] Provider health information
  def health_check
    handle_errors do
      response = self.class.get('/v1/models', headers: api_headers)

      if response.success?
        models = response.parsed_response['data'] || []
        model_available = models.any? { |model| model['id'] == @options[:model] }
        {
          status:           'healthy',
          provider:         'anthropic',
          reachable:        true,
          models_available: models.map { |model| model['id'] },
          model:            { name: @options[:model], available: model_available },
          ready:            model_available,
        }
      else
        {
          status: 'unhealthy', provider: 'anthropic', reachable: true,
          error: "HTTP #{response.code}", message: response.message, ready: false
        }
      end
    end
  rescue Prescient::Error => e
    {
      status:    'unavailable',
      provider:  'anthropic',
      reachable: false,
      error:     e.class.name,
      message:   e.message,
      ready:     false,
    }
  end

  # Return models available to the configured Anthropic account.
  # @return [Array<Hash>] Model descriptors
  def list_models
    handle_errors do
      response = self.class.get('/v1/models', headers: api_headers)
      validate_response!(response, 'model listing')

      (response.parsed_response['data'] || []).map do |model|
        {
          name:             model['id'],
          type:             'text',
          display_name:     model['display_name'],
          created_at:       model['created_at'],
          max_input_tokens: model['max_input_tokens'],
          max_tokens:       model['max_tokens'],
        }.compact
      end
    end
  end

  protected

  def validate_configuration!
    required_options = [:api_key, :model]
    missing_options = required_options.select { |opt| @options[opt].nil? }

    return unless missing_options.any?

    raise Prescient::Error, "Missing required options: #{missing_options.join(', ')}"
  end

  private

  def api_headers
    {
      'Content-Type'      => 'application/json',
      'x-api-key'         => @options[:api_key],
      'anthropic-version' => '2023-06-01',
    }
  end
end
