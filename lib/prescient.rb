# frozen_string_literal: true

require_relative 'prescient/version'

# Main Prescient module for AI provider abstraction
#
# Prescient provides a unified interface for working with multiple AI providers
# including Ollama, OpenAI, Anthropic, and HuggingFace. It supports both
# embedding generation and text completion with configurable context handling.
#
# @example Basic usage
#   Prescient.configure do |config|
#     config.add_provider(:openai, Prescient::Provider::OpenAI,
#                         api_key: 'your-api-key')
#   end
#
#   client = Prescient.client(:openai)
#   response = client.generate_response("Hello, world!")
#
# @example Embedding generation
#   embedding = client.generate_embedding("Some text to embed")
#   puts embedding.length # => 1536 (for OpenAI text-embedding-3-small)
#
# @author Claude Code
# @since 1.0.0
module Prescient
  # Base error class for all Prescient-specific errors
  class Error < StandardError; end

  # Raised when there are connection issues with AI providers
  class ConnectionError < Error; end

  # Raised when API authentication fails
  class AuthenticationError < Error; end

  # Raised when API rate limits are exceeded
  class RateLimitError < Error; end

  # Raised when a requested model is not available
  class ModelNotAvailableError < Error; end

  # Raised when AI provider returns invalid or malformed responses
  class InvalidResponseError < Error; end

  # Container module for AI provider implementations
  #
  # All provider classes should be defined within this module and inherit
  # from {Prescient::Base}.
  module Provider
    # Module for AI provider implementations
  end
end

require_relative 'prescient/base'
require_relative 'prescient/provider/ollama'
require_relative 'prescient/provider/anthropic'
require_relative 'prescient/provider/openai'
require_relative 'prescient/provider/huggingface'
require_relative 'prescient/client'

module Prescient
  # Configure Prescient with custom settings and providers
  #
  # @example Configure with custom provider
  #   Prescient.configure do |config|
  #     config.default_provider = :openai
  #     config.timeout = 60
  #     config.add_provider(:openai, Prescient::Provider::OpenAI,
  #                         api_key: 'your-key')
  #   end
  #
  # @yield [config] Configuration block
  # @yieldparam config [Configuration] The configuration object
  # @return [void]
  def self.configure
    yield(configuration)
  end

  # Get the current configuration instance
  #
  # @return [Configuration] The current configuration
  def self.configuration
    @_configuration ||= Configuration.new
  end

  # Reset configuration to defaults
  #
  # @return [Configuration] New configuration instance
  def self.reset_configuration!
    @_configuration = Configuration.new
  end

  # Configuration class for managing Prescient settings and providers
  #
  # Handles global settings like timeouts and retry behavior, as well as
  # provider registration and instantiation.
  class Configuration
    # @return [Symbol] The default provider to use when none specified
    attr_accessor :default_provider

    # @return [Integer] Default timeout in seconds for API requests
    attr_accessor :timeout

    # @return [Integer] Number of retry attempts for failed requests
    attr_accessor :retry_attempts

    # @return [Float] Delay between retry attempts in seconds
    attr_accessor :retry_delay

    # @return [Hash] Registered providers configuration
    attr_reader :providers

    # Initialize configuration with default values
    def initialize
      @default_provider = :ollama
      @timeout = 30
      @retry_attempts = 3
      @retry_delay = 1.0
      @providers = {}
    end

    # Register a new AI provider
    #
    # @param name [Symbol] Unique identifier for the provider
    # @param provider_class [Class] Provider class that inherits from Base
    # @param options [Hash] Configuration options for the provider
    # @option options [String] :api_key API key for authenticated providers
    # @option options [String] :url Base URL for self-hosted providers
    # @option options [String] :model, :chat_model Model name for text generation
    # @option options [String] :embedding_model Model name for embeddings
    # @return [void]
    #
    # @example Add OpenAI provider
    #   config.add_provider(:openai, Prescient::Provider::OpenAI,
    #                       api_key: 'sk-...',
    #                       chat_model: 'gpt-4')
    def add_provider(name, provider_class, **options)
      @providers[name.to_sym] = {
        class:   provider_class,
        options: options,
      }
    end

    # Instantiate a provider by name
    #
    # @param name [Symbol] The provider name
    # @return [Base, nil] Provider instance or nil if not found
    def provider(name)
      provider_config = @providers[name.to_sym]
      return nil unless provider_config

      provider_config[:class].new(**provider_config[:options])
    end
  end

  # Default configuration
  configure do |config|
    config.add_provider(:ollama, Prescient::Provider::Ollama,
                        url:             ENV.fetch('OLLAMA_URL', 'http://localhost:11434'),
                        embedding_model: ENV.fetch('OLLAMA_EMBEDDING_MODEL', 'nomic-embed-text'),
                        chat_model:      ENV.fetch('OLLAMA_CHAT_MODEL', 'llama3.1:8b'))

    config.add_provider(:anthropic, Prescient::Provider::Anthropic,
                        api_key: ENV.fetch('ANTHROPIC_API_KEY', nil),
                        model:   ENV.fetch('ANTHROPIC_MODEL', 'claude-3-haiku-20240307'))

    config.add_provider(:openai, Prescient::Provider::OpenAI,
                        api_key:         ENV.fetch('OPENAI_API_KEY', nil),
                        embedding_model: ENV.fetch('OPENAI_EMBEDDING_MODEL', 'text-embedding-3-small'),
                        chat_model:      ENV.fetch('OPENAI_CHAT_MODEL', 'gpt-3.5-turbo'))

    config.add_provider(:huggingface, Prescient::Provider::HuggingFace,
                        api_key:         ENV.fetch('HUGGINGFACE_API_KEY', nil),
                        embedding_model: ENV.fetch('HUGGINGFACE_EMBEDDING_MODEL', 'sentence-transformers/all-MiniLM-L6-v2'),
                        chat_model:      ENV.fetch('HUGGINGFACE_CHAT_MODEL', 'microsoft/DialoGPT-medium'))
  end
end
