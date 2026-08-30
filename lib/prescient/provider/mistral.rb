# frozen_string_literal: true

require "httparty"

module Prescient
  module Provider
    # Mistral AI API provider adapter.
    class Mistral < Prescient::Base
      include HTTParty

      base_uri "https://api.mistral.ai"

      def initialize(**options)
        super
        self.class.default_timeout(@options[:timeout] || 60)
      end

      # Generate an embedding through Mistral's embeddings API.
      # @param text [String] Text to embed
      # @return [Array<Float>] Embedding vector
      def generate_embedding(text, **options)
        handle_errors do
          embedding_model = options[:model] || @options[:embedding_model]
          response = self.class.post(
            "/v1/embeddings",
            headers: api_headers,
            body: {
              model: embedding_model,
              input: clean_text(text)
            }.to_json
          )

          validate_response!(response, "embedding generation")

          embedding = response.parsed_response.dig("data", 0, "embedding")
          raise Prescient::InvalidResponseError, "No embedding returned" unless embedding.is_a?(Array)

          expected_dimensions = @options[:embedding_dimensions]
          expected_dimensions ? validate_embedding_dimensions(embedding, expected_dimensions) : embedding
        end
      end

      # Generate a response through Mistral's chat completions API.
      # @param prompt [String] Prompt to send
      # @param context_items [Array<Hash, String>] Optional context items
      # @return [Hash] Normalized response data
      def generate_response(prompt, context_items = [], **options)
        handle_errors do
          model = options[:model] || @options[:chat_model]
          response = self.class.post(
            "/v1/chat/completions",
            headers: api_headers,
            body: {
              model: model,
              messages: [{ role: "user", content: build_prompt(prompt, context_items) }],
              max_tokens: options[:max_tokens] || 2000,
              temperature: options[:temperature] || 0.7,
              top_p: options[:top_p] || 0.9
            }.to_json
          )

          validate_response!(response, "text generation")

          parsed_response = response.parsed_response
          content = normalize_content(parsed_response.dig("choices", 0, "message", "content"))
          raise Prescient::InvalidResponseError, "No response generated" if content.nil? || content.empty?

          {
            response: content.strip,
            model: model,
            provider: "mistral",
            processing_time: nil,
            metadata: {
              usage: parsed_response["usage"],
              finish_reason: parsed_response.dig("choices", 0, "finish_reason")
            }
          }
        end
      end

      # Check whether the configured Mistral models are available.
      # @return [Hash] Provider health information
      def health_check
        handle_errors do
          response = self.class.get("/v1/models", headers: api_headers)

          if response.success?
            models = response.parsed_response["data"] || []
            embedding_available = model_available?(models, @options[:embedding_model])
            chat_available = model_available?(models, @options[:chat_model])

            {
              status: "healthy",
              provider: "mistral",
              reachable: true,
              models_available: models.map { |model| model["id"] },
              embedding_model: { name: @options[:embedding_model], available: embedding_available },
              chat_model: { name: @options[:chat_model], available: chat_available },
              ready: embedding_available && chat_available
            }
          else
            {
              status: "unhealthy",
              provider: "mistral",
              reachable: true,
              error: "HTTP #{response.code}",
              message: response.message,
              ready: false
            }
          end
        end
      rescue Prescient::Error => e
        {
          status: "unavailable",
          provider: "mistral",
          reachable: false,
          error: e.class.name,
          message: e.message,
          ready: false
        }
      end

      # List models available to the configured Mistral API key.
      # @return [Array<Hash>] Model descriptors
      def list_models
        handle_errors do
          response = self.class.get("/v1/models", headers: api_headers)
          validate_response!(response, "model listing")

          (response.parsed_response["data"] || []).map do |model|
            {
              name: model["id"],
              object: model["object"],
              created: model["created"],
              owned_by: model["owned_by"],
              capabilities: model["capabilities"],
              max_context_length: model["max_context_length"]
            }.compact
          end
        end
      end

      protected

      def validate_configuration!
        required_options = %i[api_key embedding_model chat_model]
        missing_options = required_options.select { |option| @options[option].nil? }

        return unless missing_options.any?

        raise Prescient::Error, "Missing required options: #{missing_options.join(", ")}"
      end

      private

      def api_headers
        {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer #{@options[:api_key]}"
        }
      end

      def model_available?(models, model_name)
        models.any? { |model| model["id"] == model_name }
      end

      def normalize_content(content)
        return content if content.is_a?(String)
        return unless content.is_a?(Array)

        content.filter_map { |part| part["text"] if part.is_a?(Hash) }.join
      end
    end
  end
end
