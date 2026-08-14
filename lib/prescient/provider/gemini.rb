# frozen_string_literal: true

require 'httparty'

# Google Gemini API provider adapter.
class Prescient::Provider::Gemini < Prescient::Base
  include HTTParty

  base_uri 'https://generativelanguage.googleapis.com'

  def initialize(**options)
    super
    self.class.default_timeout(@options[:timeout] || 60)
  end

  # Generate an embedding through Gemini's embedContent endpoint.
  # @param text [String] Text to embed
  # @return [Array<Float>] Embedding vector
  def generate_embedding(text, **options)
    handle_errors do
      embedding_model = options[:model] || @options[:embedding_model]
      response = self.class.post(
        model_endpoint(embedding_model, 'embedContent'),
        headers: api_headers,
        body:    {
          content: { parts: [{ text: clean_text(text) }] },
        }.to_json,
      )

      validate_response!(response, 'embedding generation')

      embedding = response.parsed_response.dig('embedding', 'values')
      raise Prescient::InvalidResponseError, 'No embedding returned' unless embedding.is_a?(Array)

      expected_dimensions = @options[:embedding_dimensions]
      expected_dimensions ? validate_embedding_dimensions(embedding, expected_dimensions) : embedding
    end
  end

  # Generate a response through Gemini's generateContent endpoint.
  # @param prompt [String] Prompt to send
  # @param context_items [Array<Hash, String>] Optional context items
  # @return [Hash] Normalized response data
  def generate_response(prompt, context_items = [], **options)
    handle_errors do
      model = options[:model] || @options[:chat_model]
      response = self.class.post(
        model_endpoint(model, 'generateContent'),
        headers: api_headers,
        body:    {
          contents:         [{ role: 'user', parts: [{ text: build_prompt(prompt, context_items) }] }],
          generationConfig: {
            maxOutputTokens: options[:max_tokens] || 2000,
            temperature:     options[:temperature] || 0.7,
            topP:            options[:top_p] || 0.9,
          },
        }.to_json,
      )

      validate_response!(response, 'text generation')

      parsed_response = response.parsed_response
      parts = parsed_response.dig('candidates', 0, 'content', 'parts')
      content = Array(parts).filter_map { |part| part['text'] }.join
      raise Prescient::InvalidResponseError, 'No response generated' if content.nil? || content.empty?

      {
        response:        content.strip,
        model:           model,
        provider:        'gemini',
        processing_time: nil,
        metadata:        {
          usage:         parsed_response['usageMetadata'],
          finish_reason: parsed_response.dig('candidates', 0, 'finishReason'),
        },
      }
    end
  end

  # Check whether the configured Gemini models are available.
  # @return [Hash] Provider health information
  def health_check
    handle_errors do
      response = self.class.get('/v1beta/models', headers: api_headers)

      if response.success?
        models = response.parsed_response['models'] || []
        embedding_model = find_model(models, @options[:embedding_model], 'embedContent')
        chat_model = find_model(models, @options[:chat_model], 'generateContent')

        {
          status:           'healthy',
          provider:         'gemini',
          reachable:        true,
          models_available: models.map { |model| model['name'].to_s.delete_prefix('models/') },
          embedding_model:  { name: @options[:embedding_model], available: embedding_model },
          chat_model:       { name: @options[:chat_model], available: chat_model },
          ready:            embedding_model && chat_model,
        }
      else
        {
          status:    'unhealthy',
          provider:  'gemini',
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
      provider:  'gemini',
      reachable: false,
      error:     e.class.name,
      message:   e.message,
      ready:     false,
    }
  end

  # List models available to the configured Gemini API key.
  # @return [Array<Hash>] Model descriptors
  def list_models
    handle_errors do
      response = self.class.get('/v1beta/models', headers: api_headers)
      validate_response!(response, 'model listing')

      (response.parsed_response['models'] || []).map do |model|
        {
          name:                       model['name'].to_s.delete_prefix('models/'),
          display_name:               model['displayName'],
          supported_generation_modes: model['supportedGenerationMethods'],
          input_token_limit:          model['inputTokenLimit'],
          output_token_limit:         model['outputTokenLimit'],
        }.compact
      end
    end
  end

  protected

  def validate_configuration!
    required_options = [:api_key, :embedding_model, :chat_model]
    missing_options = required_options.select { |option| @options[option].nil? }

    return unless missing_options.any?

    raise Prescient::Error, "Missing required options: #{missing_options.join(', ')}"
  end

  private

  def api_headers
    {
      'Content-Type'   => 'application/json',
      'x-goog-api-key' => @options[:api_key],
    }
  end

  def model_endpoint(model, operation)
    model_name = model.to_s.delete_prefix('models/')
    "/v1beta/models/#{model_name}:#{operation}"
  end

  def find_model(models, model_name, operation)
    models.any? do |model|
      model['name'].to_s.delete_prefix('models/') == model_name &&
        model.fetch('supportedGenerationMethods', []).include?(operation)
    end
  end
end
