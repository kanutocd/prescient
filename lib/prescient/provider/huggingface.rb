# frozen_string_literal: true

require "httparty"

module Prescient
  module Provider
    # Hugging Face router-backed Inference Providers API adapter.
    class HuggingFace < Prescient::Base
      include HTTParty

      base_uri "https://router.huggingface.co"

      # Router path for the Hugging Face feature-extraction provider.
      # @return [String] Feature-extraction endpoint template
      FEATURE_EXTRACTION_PATH = "/hf-inference/models/%<model>s/pipeline/feature-extraction"

      # OpenAI-compatible router path for Hugging Face chat completions.
      # @return [String] Chat-completions endpoint path
      CHAT_COMPLETIONS_PATH = "/v1/chat/completions"

      # OpenAI-compatible router path for listing available chat models.
      # @return [String] Model-list endpoint path
      MODEL_LIST_PATH = "/v1/models"

      # Known embedding dimensions for commonly used models.
      EMBEDDING_DIMENSIONS = {
        "sentence-transformers/all-MiniLM-L6-v2" => 384,
        "sentence-transformers/all-mpnet-base-v2" => 768,
        "sentence-transformers/all-roberta-large-v1" => 1024
      }.freeze

      def initialize(**options)
        super
        @provider_name = "Hugging Face"
        self.class.default_timeout(@options[:timeout] || 60)
      end

      # Generate an embedding through Hugging Face feature extraction.
      # @param text [String] Text to embed
      # @return [Array<Float>] Embedding vector
      def generate_embedding(text, **options)
        handle_errors do
          clean_text_input = clean_text(text)

          embedding_model = options[:model] || @options[:embedding_model]
          response = self.class.post(format(FEATURE_EXTRACTION_PATH, model: embedding_model),
                                     headers: {
                                       "Content-Type" => "application/json",
                                       "Authorization" => "Bearer #{@options[:api_key]}"
                                     },
                                     body: { inputs: clean_text_input }.to_json)

          validate_response!(response, "embedding generation")

          # HuggingFace returns embeddings as nested arrays, get the first one
          embedding_data = response.parsed_response
          embedding_data = embedding_data.first if embedding_data.is_a?(Array) && embedding_data.first.is_a?(Array)

          raise Prescient::InvalidResponseError, "No embedding returned" unless embedding_data.is_a?(Array)

          expected_dimensions = EMBEDDING_DIMENSIONS[embedding_model] || @options[:embedding_dimensions]
          unless expected_dimensions
            raise Prescient::Error,
                  "Embedding dimensions are required for model #{embedding_model}"
          end

          validate_embedding_dimensions(embedding_data, expected_dimensions)
        end
      end

      # Generate text through a Hugging Face text-generation model.
      # @param prompt [String] Prompt to send
      # @param context_items [Array<Hash, String>] Optional context items
      # @return [Hash] Normalized response data
      def generate_response(prompt, context_items = [], **options)
        handle_errors do
          formatted_prompt = build_prompt(prompt, context_items)

          response = self.class.post(CHAT_COMPLETIONS_PATH,
                                     headers: {
                                       "Content-Type" => "application/json",
                                       "Authorization" => "Bearer #{@options[:api_key]}"
                                     },
                                     body: {
                                       model: options[:model] || @options[:chat_model],
                                       messages: [{ role: "user", content: formatted_prompt }],
                                       max_tokens: options[:max_tokens] || 2000,
                                       temperature: options[:temperature] || 0.7,
                                       top_p: options[:top_p] || 0.9
                                     }.to_json)

          validate_response!(response, "text generation")

          parsed_response = response.parsed_response
          generated_text = parsed_response.dig("choices", 0, "message", "content") if parsed_response.is_a?(Hash)
          raise Prescient::InvalidResponseError, "No response generated" unless generated_text

          {
            response: generated_text.strip,
            model: options[:model] || @options[:chat_model],
            provider: "huggingface",
            processing_time: nil,
            metadata: {
              usage: parsed_response["usage"],
              finish_reason: parsed_response.dig("choices", 0, "finish_reason")
            }
          }
        end
      end

      # Check availability of the configured embedding and text models.
      #
      # The embedding model is checked against the model metadata API on
      # `huggingface.co`, while the chat model is checked against the router's
      # OpenAI-compatible `/v1/models` listing. `ready` requires both checks to
      # succeed.
      #
      # @return [Hash] Provider health information
      def health_check
        handle_errors do
          embedding_response = self.class.get("https://huggingface.co/api/models/#{@options[:embedding_model]}",
                                              headers: { "Authorization" => "Bearer #{@options[:api_key]}" })
          chat_response = self.class.get(MODEL_LIST_PATH,
                                         headers: { "Authorization" => "Bearer #{@options[:api_key]}" })

          embedding_healthy = embedding_response.success?
          chat_models = chat_response.parsed_response["data"] || []
          chat_healthy = chat_response.success? && chat_models.any? { |model| model["id"] == @options[:chat_model] }

          {
            status: embedding_healthy && chat_healthy ? "healthy" : "partial",
            provider: "huggingface",
            reachable: true,
            embedding_model: {
              name: @options[:embedding_model],
              available: embedding_healthy
            },
            chat_model: {
              name: @options[:chat_model],
              available: chat_healthy
            },
            ready: embedding_healthy && chat_healthy
          }
        end
      rescue Prescient::Error => e
        {
          status: "unavailable",
          provider: "huggingface",
          reachable: false,
          error: e.class.name,
          message: e.message,
          ready: false
        }
      end

      # Return the configured Hugging Face models.
      #
      # This method does not query the Hugging Face APIs. It reflects the current
      # adapter configuration only.
      #
      # @return [Array<Hash>] Model descriptors
      def list_models
        # HuggingFace doesn't provide a simple API to list all models
        # Return the configured models
        [
          {
            name: @options[:embedding_model],
            type: "embedding",
            dimensions: EMBEDDING_DIMENSIONS[@options[:embedding_model]]
          },
          {
            name: @options[:chat_model],
            type: "text-generation"
          }
        ]
      end

      protected

      def validate_configuration!
        missing_options = %i[api_key embedding_model chat_model].select { |opt| @options[opt].nil? }
        return unless missing_options.any?

        raise Prescient::Error, "Missing required options: #{missing_options.join(", ")}"
      end

      private

      def provider_error(message, response, operation:, provider: nil, error_class: Prescient::ProviderError)
        if response.code == 503
          # HuggingFace model loading
          error_body = begin
            response.parsed_response
          rescue StandardError
            nil
          end
          if error_body.is_a?(Hash) && error_body["error"]&.include?("loading")
            message = "Model is loading, please try again later"
          end
        end

        super
      end
    end
  end
end
