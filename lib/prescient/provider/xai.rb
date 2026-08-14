# frozen_string_literal: true

require 'httparty'

# xAI API provider adapter.
class Prescient::Provider::XAI < Prescient::Base
  include HTTParty

  base_uri 'https://api.x.ai'

  def initialize(**options)
    super
    @provider_name = 'xAI'
    self.class.default_timeout(@options[:timeout] || 60)
  end

  # xAI does not expose a standard embeddings API for this adapter.
  # @raise [Prescient::Error] Always, because embeddings are unsupported
  def generate_embedding(_text, **_options)
    raise Prescient::Error, 'xAI provider does not support embeddings.'
  end

  # Generate a response through xAI's OpenAI-compatible chat API.
  # @param prompt [String] Prompt to send
  # @param context_items [Array<Hash, String>] Optional context items
  # @return [Hash] Normalized response data
  def generate_response(prompt, context_items = [], **options)
    handle_errors do
      model = options[:model] || @options[:chat_model]
      response = self.class.post(
        '/v1/chat/completions',
        headers: api_headers,
        body:    {
          model:       model,
          messages:    [{ role: 'user', content: build_prompt(prompt, context_items) }],
          max_tokens:  options[:max_tokens] || 2000,
          temperature: options[:temperature] || 0.7,
          top_p:       options[:top_p] || 0.9,
        }.to_json,
      )

      validate_response!(response, 'text generation')

      parsed_response = response.parsed_response
      content = parsed_response.dig('choices', 0, 'message', 'content')
      raise Prescient::InvalidResponseError, 'No response generated' unless content.is_a?(String) && !content.empty?

      {
        response:        content.strip,
        model:           model,
        provider:        'xai',
        processing_time: nil,
        metadata:        {
          usage:         parsed_response['usage'],
          finish_reason: parsed_response.dig('choices', 0, 'finish_reason'),
        },
      }
    end
  end

  # Check whether the configured xAI model is available.
  # @return [Hash] Provider health information
  def health_check
    handle_errors do
      response = self.class.get('/v1/models', headers: api_headers)

      if response.success?
        models = response.parsed_response['data'] || []
        model_available = models.any? { |model| model['id'] == @options[:chat_model] }

        {
          status:           'healthy',
          provider:         'xai',
          reachable:        true,
          models_available: models.map { |model| model['id'] },
          chat_model:       { name: @options[:chat_model], available: model_available },
          ready:            model_available,
        }
      else
        {
          status:    'unhealthy',
          provider:  'xai',
          reachable: true,
          error:     "HTTP #{response.code}",
          message:   response.message,
          ready:     false,
        }
      end
    end
  rescue Prescient::Error => e
    {
      status:    'unavailable',
      provider:  'xai',
      reachable: false,
      error:     e.class.name,
      message:   e.message,
      ready:     false,
    }
  end

  # List models available to the configured xAI API key.
  # @return [Array<Hash>] Model descriptors
  def list_models
    handle_errors do
      response = self.class.get('/v1/models', headers: api_headers)
      validate_response!(response, 'model listing')

      (response.parsed_response['data'] || []).map do |model|
        {
          name:           model['id'],
          object:         model['object'],
          created:        model['created'],
          owned_by:       model['owned_by'],
          context_length: model['context_length'],
        }.compact
      end
    end
  end

  protected

  def validate_configuration!
    required_options = [:api_key, :chat_model]
    missing_options = required_options.select { |option| @options[option].nil? }

    return unless missing_options.any?

    raise Prescient::Error, "Missing required options: #{missing_options.join(', ')}"
  end

  private

  def api_headers
    {
      'Content-Type'  => 'application/json',
      'Authorization' => "Bearer #{@options[:api_key]}",
    }
  end
end
