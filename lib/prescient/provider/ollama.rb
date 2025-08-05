# frozen_string_literal: true

require 'httparty'

class Prescient::Provider::Ollama < Prescient::Base
  include HTTParty

  EMBEDDING_DIMENSIONS = 768 # nomic-embed-text dimensions

  def initialize(**options)
    super
    self.class.base_uri(@options[:url])
    self.class.default_timeout(@options[:timeout] || 60)
  end

  def generate_embedding(text, **_options)
    handle_errors do
      embedding = fetch_and_parse('post', '/api/embeddings',
                                  root_key: 'embedding',
                                  headers:  { 'Content-Type' => 'application/json' },
                                  body:     {
                                    model:  @options[:embedding_model],
                                    prompt: clean_text(text),
                                  }.to_json)

      raise Prescient::InvalidResponseError, 'No embedding returned' unless embedding

      normalize_embedding(embedding, EMBEDDING_DIMENSIONS)
    end
  end

  def generate_response(prompt, context_items = [], **options)
    handle_errors do
      generated_text = fetch_and_parse('post', '/api/generate',
                                       prepare_generate_response(prompt, context_items, **options))
      raise Prescient::InvalidResponseError, 'No response generated' unless generated_text

      {
        response:        generated_text.strip,
        model:           @options[:chat_model],
        provider:        'ollama',
        processing_time: response.parsed_response['total_duration']&./(1_000_000_000.0),
        metadata:        {
          eval_count:        response.parsed_response['eval_count'],
          eval_duration:     response.parsed_response['eval_duration'],
          prompt_eval_count: response.parsed_response['prompt_eval_count'],
        },
      }
    end
  end

  def health_check
    handle_errors do
      models = available_models
      hash = {
        status:           'healthy',
        provider:         'ollama',
        url:              @options[:url],
        models_available: models.map { |m| m['name'] },
        embedding_model:  {
          name:      @options[:embedding_model],
          available: models.any? { |m| m[:embedding] },
        },
        chat_model:       {
          name:      @options[:chat_model],
          available: models.any? { |m| m[:chat] },
        },
      }
      hash.merge(ready: models[:embedding][:ready] && models[:chat][:ready])
    end
  rescue Prescient::Error => e
    {
      status:   'unavailable',
      provider: 'ollama',
      error:    e.class.name,
      message:  e.message,
      url:      @options[:url],
    }
  end

  def available_models
    return @_available_models if defined?(@_available_models)

    handle_errors do
      @_available_models = (fetch_and_parse('get', '/api/tags', root_key: 'models') || []).map { |model|
        { embedding:  model['name'] == @options[:embedding_model],
          chat:       model['name'] == @options[:chat_model],
          name: model['name'], size: model['size'], modified_at: model['modified_at'], digest: model['digest'] }
      }
    end
  end

  def pull_model(model_name)
    handle_errors do
      fetch_and_parse('post', '/api/pull',
                      headers: { 'Content-Type' => 'application/json' },
                      body:    { name: model_name }.to_json,
                      timeout: 300) # 5 minutes for model download
      {
        success: true,
        model:   model_name,
        message: "Model #{model_name} pulled successfully",
      }
    end
  end

  protected

  def validate_configuration!
    required_options = [:url, :embedding_model, :chat_model]
    missing_options = required_options.select { |opt| @options[opt].nil? }

    return unless missing_options.any?

    raise Prescient::Error, "Missing required options: #{missing_options.join(', ')}"
  end

  private

  def prepare_generate_response(prompt, context_items = [], **options)
    formatted_prompt = build_prompt(prompt, context_items)
    { root_key: 'response',
      headers:  { 'Content-Type' => 'application/json' },
      body:     {
        model:   @options[:chat_model],
        prompt:  formatted_prompt,
        stream:  false,
        options: {
          num_predict: options[:max_tokens] || 2000,
          temperature: options[:temperature] || 0.7,
          top_p:       options[:top_p] || 0.9,
        },
      }.to_json }
  end

  def fetch_and_parse(htt_verb, endpoint, **options)
    options = options.dup
    root_key = options.delete(:root_key)

    response = self.class.send(htt_verb, endpoint, **options)
    validate_response!(response, "#{htt_verb.upcase} #{endpoint}")
    return unless root_key

    response.parsed_response[root_key]
  end

  def validate_response!(response, operation)
    return if response.success?

    case response.code
    when 404
      raise Prescient::ModelNotAvailableError, "Model not available for #{operation}"
    when 429
      raise Prescient::RateLimitError, "Rate limit exceeded for #{operation}"
    when 401, 403
      raise Prescient::AuthenticationError, "Authentication failed for #{operation}"
    when 500..599
      raise Prescient::Error, "Ollama server error during #{operation}: #{response.body}"
    else
      raise Prescient::Error,
            "Ollama request failed for #{operation}: HTTP #{response.code} - #{response.message}"
    end
  end
end
