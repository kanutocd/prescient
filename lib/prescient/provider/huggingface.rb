# frozen_string_literal: true

require 'httparty'

class Prescient::Provider::HuggingFace < Prescient::Base
  include HTTParty

  base_uri 'https://api-inference.huggingface.co'

  EMBEDDING_DIMENSIONS = {
    'sentence-transformers/all-MiniLM-L6-v2'     => 384,
    'sentence-transformers/all-mpnet-base-v2'    => 768,
    'sentence-transformers/all-roberta-large-v1' => 1024,
  }.freeze

  def initialize(**options)
    super
    self.class.default_timeout(@options[:timeout] || 60)
  end

  def generate_embedding(text, **_options)
    handle_errors do
      clean_text_input = clean_text(text)

      response = self.class.post("/pipeline/feature-extraction/#{@options[:embedding_model]}",
                                 headers: {
                                   'Content-Type'  => 'application/json',
                                   'Authorization' => "Bearer #{@options[:api_key]}",
                                 },
                                 body:    {
                                   inputs:  clean_text_input,
                                   options: {
                                     wait_for_model: true,
                                   },
                                 }.to_json)

      validate_response!(response, 'embedding generation')

      # HuggingFace returns embeddings as nested arrays, get the first one
      embedding_data = response.parsed_response
      embedding_data = embedding_data.first if embedding_data.is_a?(Array) && embedding_data.first.is_a?(Array)

      raise Prescient::InvalidResponseError, 'No embedding returned' unless embedding_data.is_a?(Array)

      expected_dimensions = EMBEDDING_DIMENSIONS[@options[:embedding_model]] || 384
      normalize_embedding(embedding_data, expected_dimensions)
    end
  end

  def generate_response(prompt, context_items = [], **options)
    handle_errors do
      formatted_prompt = build_prompt(prompt, context_items)

      response = self.class.post("/models/#{@options[:chat_model]}",
                                 headers: {
                                   'Content-Type'  => 'application/json',
                                   'Authorization' => "Bearer #{@options[:api_key]}",
                                 },
                                 body:    {
                                   inputs:     formatted_prompt,
                                   parameters: {
                                     max_new_tokens:   options[:max_tokens] || 2000,
                                     temperature:      options[:temperature] || 0.7,
                                     top_p:            options[:top_p] || 0.9,
                                     return_full_text: false,
                                   },
                                   options:    {
                                     wait_for_model: true,
                                   },
                                 }.to_json)

      validate_response!(response, 'text generation')

      # HuggingFace returns different formats depending on the model
      generated_text = nil
      parsed_response = response.parsed_response

      if parsed_response.is_a?(Array) && parsed_response.first.is_a?(Hash)
        generated_text = parsed_response.first['generated_text']
      elsif parsed_response.is_a?(Hash)
        generated_text = parsed_response['generated_text'] || parsed_response['text']
      end

      raise Prescient::InvalidResponseError, 'No response generated' unless generated_text

      {
        response:        generated_text.strip,
        model:           @options[:chat_model],
        provider:        'huggingface',
        processing_time: nil,
        metadata:        {},
      }
    end
  end

  def health_check
    handle_errors do
      # Test embedding model
      embedding_response = self.class.post("/pipeline/feature-extraction/#{@options[:embedding_model]}",
                                           headers: {
                                             'Authorization' => "Bearer #{@options[:api_key]}",
                                           },
                                           body:    { inputs: 'test' }.to_json)

      # Test chat model
      chat_response = self.class.post("/models/#{@options[:chat_model]}",
                                      headers: {
                                        'Authorization' => "Bearer #{@options[:api_key]}",
                                      },
                                      body:    {
                                        inputs:     'test',
                                        parameters: { max_new_tokens: 5 },
                                      }.to_json)

      embedding_healthy = embedding_response.success?
      chat_healthy = chat_response.success?

      {
        status:          embedding_healthy && chat_healthy ? 'healthy' : 'partial',
        provider:        'huggingface',
        embedding_model: {
          name:      @options[:embedding_model],
          available: embedding_healthy,
        },
        chat_model:      {
          name:      @options[:chat_model],
          available: chat_healthy,
        },
        ready:           embedding_healthy && chat_healthy,
      }
    end
  rescue Prescient::ConnectionError => e
    {
      status:   'unavailable',
      provider: 'huggingface',
      error:    e.class.name,
      message:  e.message,
    }
  end

  def list_models
    # HuggingFace doesn't provide a simple API to list all models
    # Return the configured models
    [
      {
        name:       @options[:embedding_model],
        type:       'embedding',
        dimensions: EMBEDDING_DIMENSIONS[@options[:embedding_model]],
      },
      {
        name: @options[:chat_model],
        type: 'text-generation',
      },
    ]
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
    when 503
      # HuggingFace model loading
      error_body = begin
        response.parsed_response
      rescue StandardError
        response.body
      end
      if error_body.is_a?(Hash) && error_body['error']&.include?('loading')
        raise Prescient::Error, 'Model is loading, please try again later'
      end

      raise Prescient::Error, "HuggingFace service unavailable for #{operation}"

    when 500..599
      raise Prescient::Error, "HuggingFace server error during #{operation}: #{response.body}"
    else
      raise Prescient::Error,
            "HuggingFace request failed for #{operation}: HTTP #{response.code} - #{response.message}"
    end
  end
end
