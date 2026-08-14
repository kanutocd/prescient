# frozen_string_literal: true

require 'httparty'

# OpenAI API provider adapter.
class Prescient::Provider::OpenAI < Prescient::Base
  include HTTParty

  base_uri 'https://api.openai.com'

  # Known embedding dimensions for OpenAI embedding models.
  EMBEDDING_DIMENSIONS = {
    'text-embedding-3-small' => 1536,
    'text-embedding-3-large' => 3072,
    'text-embedding-ada-002' => 1536,
  }.freeze

  def initialize(**options)
    super
    self.class.default_timeout(@options[:timeout] || 60)
  end

  # Generate an embedding through the OpenAI embeddings API.
  # @param text [String] Text to embed
  # @return [Array<Float>] Embedding vector
  def generate_embedding(text, **_options)
    handle_errors do
      clean_text_input = clean_text(text)

      response = self.class.post('/v1/embeddings',
                                 headers: {
                                   'Content-Type'  => 'application/json',
                                   'Authorization' => "Bearer #{@options[:api_key]}",
                                 },
                                 body:    {
                                   model:           @options[:embedding_model],
                                   input:           clean_text_input,
                                   encoding_format: 'float',
                                 }.to_json)

      validate_response!(response, 'embedding generation')

      embedding_data = response.parsed_response.dig('data', 0, 'embedding')
      raise Prescient::InvalidResponseError, 'No embedding returned' unless embedding_data

      expected_dimensions = EMBEDDING_DIMENSIONS[@options[:embedding_model]] || @options[:embedding_dimensions]
      unless expected_dimensions
        raise Prescient::Error,
              "Embedding dimensions are required for model #{@options[:embedding_model]}"
      end

      validate_embedding_dimensions(embedding_data, expected_dimensions)
    end
  end

  # Generate a response through the OpenAI chat completions API.
  # @param prompt [String] Prompt to send
  # @param context_items [Array<Hash, String>] Optional context items
  # @return [Hash] Normalized response data
  def generate_response(prompt, context_items = [], **options)
    handle_errors do
      formatted_prompt = build_prompt(prompt, context_items)

      response = self.class.post('/v1/chat/completions',
                                 headers: {
                                   'Content-Type'  => 'application/json',
                                   'Authorization' => "Bearer #{@options[:api_key]}",
                                 },
                                 body:    {
                                   model:       @options[:chat_model],
                                   messages:    [
                                     {
                                       role:    'user',
                                       content: formatted_prompt,
                                     },
                                   ],
                                   max_tokens:  options[:max_tokens] || 2000,
                                   temperature: options[:temperature] || 0.7,
                                   top_p:       options[:top_p] || 0.9,
                                 }.to_json)

      validate_response!(response, 'text generation')

      content = response.parsed_response.dig('choices', 0, 'message', 'content')
      raise Prescient::InvalidResponseError, 'No response generated' unless content

      {
        response:        content.strip,
        model:           @options[:chat_model],
        provider:        'openai',
        processing_time: nil,
        metadata:        {
          usage:         response.parsed_response['usage'],
          finish_reason: response.parsed_response.dig('choices', 0, 'finish_reason'),
        },
      }
    end
  end

  # Check OpenAI model availability.
  # @return [Hash] Provider health information
  def health_check
    handle_errors do
      response = self.class.get('/v1/models',
                                headers: {
                                  'Authorization' => "Bearer #{@options[:api_key]}",
                                })

      if response.success?
        models = response.parsed_response['data'] || []
        embedding_available = models.any? { |m| m['id'] == @options[:embedding_model] }
        chat_available = models.any? { |m| m['id'] == @options[:chat_model] }

        {
          status:           'healthy',
          provider:         'openai',
          reachable:        true,
          models_available: models.map { |m| m['id'] },
          embedding_model:  {
            name:      @options[:embedding_model],
            available: embedding_available,
          },
          chat_model:       {
            name:      @options[:chat_model],
            available: chat_available,
          },
          ready:            embedding_available && chat_available,
        }
      else
        {
          status:    'unhealthy',
          provider:  'openai',
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
      provider:  'openai',
      reachable: false,
      error:     e.class.name,
      message:   e.message,
      ready:     false,
    }
  end

  # List models available to the configured OpenAI account.
  # @return [Array<Hash>] Model descriptors
  def list_models
    handle_errors do
      response = self.class.get('/v1/models',
                                headers: {
                                  'Authorization' => "Bearer #{@options[:api_key]}",
                                })
      validate_response!(response, 'model listing')

      models = response.parsed_response['data'] || []
      models.map do |model|
        {
          name:     model['id'],
          created:  model['created'],
          owned_by: model['owned_by'],
        }
      end
    end
  end

  protected

  def validate_configuration!
    required_options = [:api_key, :embedding_model, :chat_model]
    missing_options = required_options.select { |opt| @options[opt].nil? }

    return unless missing_options.any?

    raise Prescient::Error, "Missing required options: #{missing_options.join(', ')}"
  end

  private

  def validate_response!(response, operation)
    return if response.success?

    case response.code
    when 400
      raise Prescient::Error, "Bad request for #{operation}: #{response.body}"
    when 401
      raise Prescient::AuthenticationError, "Authentication failed for #{operation}"
    when 403
      raise Prescient::AuthenticationError, "Forbidden access for #{operation}"
    when 429
      raise Prescient::RateLimitError, "Rate limit exceeded for #{operation}"
    when 500..599
      raise Prescient::ProviderError, "OpenAI server error during #{operation}: #{response.body}"
    else
      raise Prescient::Error,
            "OpenAI request failed for #{operation}: HTTP #{response.code} - #{response.message}"
    end
  end
end
