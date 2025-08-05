# frozen_string_literal: true

require 'httparty'

class Prescient::Provider::Anthropic < Prescient::Base
  include HTTParty

  base_uri 'https://api.anthropic.com'

  def initialize(**options)
    super
    self.class.default_timeout(@options[:timeout] || 60)
  end

  def generate_embedding(_text, **_options)
    # Anthropic doesn't provide embedding API, raise error
    raise Prescient::Error,
          'Anthropic provider does not support embeddings. Use OpenAI or HuggingFace for embeddings.'
  end

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

  def health_check
    handle_errors do
      # Test with a simple message
      response = self.class.post('/v1/messages',
                                 headers: {
                                   'Content-Type'      => 'application/json',
                                   'x-api-key'         => @options[:api_key],
                                   'anthropic-version' => '2023-06-01',
                                 },
                                 body:    {
                                   model:      @options[:model],
                                   max_tokens: 10,
                                   messages:   [
                                     {
                                       role:    'user',
                                       content: 'Test',
                                     },
                                   ],
                                 }.to_json)

      if response.success?
        {
          status:   'healthy',
          provider: 'anthropic',
          model:    @options[:model],
          ready:    true,
        }
      else
        {
          status:   'unhealthy',
          provider: 'anthropic',
          error:    "HTTP #{response.code}",
          message:  response.message,
        }
      end
    end
  rescue Prescient::ConnectionError => e
    {
      status:   'unavailable',
      provider: 'anthropic',
      error:    e.class.name,
      message:  e.message,
    }
  end

  def list_models
    # Anthropic doesn't provide a models list API
    [
      { name: 'claude-3-haiku-20240307', type: 'text' },
      { name: 'claude-3-sonnet-20240229', type: 'text' },
      { name: 'claude-3-opus-20240229', type: 'text' },
    ]
  end

  protected

  def validate_configuration!
    required_options = [:api_key, :model]
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
      raise Prescient::Error, "Anthropic server error during #{operation}: #{response.body}"
    else
      raise Prescient::Error,
            "Anthropic request failed for #{operation}: HTTP #{response.code} - #{response.message}"
    end
  end
end
