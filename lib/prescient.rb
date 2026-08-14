# frozen_string_literal: true

require_relative 'prescient/version'
require_relative 'prescient/errors'
require_relative 'prescient/pgvector'
require_relative 'prescient/base'
require_relative 'prescient/provider/ollama'
require_relative 'prescient/provider/anthropic'
require_relative 'prescient/provider/openai'
require_relative 'prescient/provider/huggingface'
require_relative 'prescient/provider/gemini'
require_relative 'prescient/provider/mistral'
require_relative 'prescient/provider/deepseek'
require_relative 'prescient/provider/xai'
require_relative 'prescient/configuration_loader'
require_relative 'prescient/client'
require_relative 'prescient/api'
require_relative 'prescient/cli'

# Main Prescient module for AI provider abstraction
#
# Prescient provides a unified interface for working with multiple AI providers
# including Ollama, OpenAI, Anthropic, and Hugging Face. It supports both
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

  # Load configuration from a YAML file and replace the current configuration.
  #
  # The loaded configuration starts from the current environment defaults,
  # then applies the YAML file, environment-variable references, and any
  # optional overrides.
  #
  # @param path [String, nil] YAML configuration file path
  # @param env [Hash] Environment variables used while loading configuration
  # @return [Configuration] The loaded configuration
  def self.load_configuration(path = nil, env: ENV)
    effective_path = path || env['PRESCIENT_CONFIG']
    configuration = if effective_path
                      ConfigurationLoader.load_file(effective_path, env:)
                    else
                      Configuration.new.tap do |config|
                        configure_default_providers(config, env)
                      end
                    end

    @_configuration = configuration
  end

  # Configuration class for managing Prescient settings and providers
  #
  # Handles global settings like timeouts and retry behavior, as well as
  # provider registration and instantiation.
  class Configuration
    # @return [Array<Symbol>] Built-in provider option keys removed from output
    DEFAULT_SENSITIVE_KEYS = [:api_key, :password, :token, :secret].freeze

    # @return [Symbol] The default provider to use when none specified
    attr_accessor :default_provider

    # @return [Integer] Default timeout in seconds for API requests
    attr_accessor :timeout

    # @return [Integer] Number of retry attempts for failed requests
    attr_accessor :retry_attempts

    # @return [Float] Delay between retry attempts in seconds
    attr_accessor :retry_delay

    # @return [Array<Symbol>] List of fallback providers to try when primary fails
    attr_accessor :fallback_providers

    # @return [Array<Symbol>] Additional keys removed from provider information
    attr_reader :sensitive_keys

    # @return [Hash] Registered providers configuration
    attr_reader :providers

    # Initialize configuration with default values
    def initialize
      @default_provider = :ollama
      @timeout = 30
      @retry_attempts = 3
      @retry_delay = 1.0
      @fallback_providers = []
      @sensitive_keys = []
      @providers = {}
      @provider_instances = {} # : Hash[Symbol, untyped]
    end

    # Configure additional keys to remove from provider information.
    # Built-in sensitive keys are always sanitized.
    #
    # @param keys [Array<Symbol, String>] Additional sensitive option keys
    # @return [Array<Symbol>] Normalized additional keys
    def sensitive_keys=(keys)
      @sensitive_keys = Array(keys).map(&:to_sym).uniq
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
    #                       chat_model: 'gpt-4.1-mini')
    def add_provider(name, provider_class, **options)
      provider_name = name.to_sym
      @providers[provider_name] = {
        class:   provider_class,
        options: options,
      }
      @provider_instances.delete(provider_name)
    end

    # Instantiate a provider by name
    #
    # @param name [Symbol] The provider name
    # @return [Base, nil] Provider instance or nil if not found
    def provider(name)
      provider_name = name.to_sym
      provider_config = @providers[provider_name]
      return nil unless provider_config

      provider_options = provider_config[:options] # : Hash[Symbol, untyped]
      @provider_instances[provider_name] ||= provider_config[:class].new(**provider_options)
    end

    # Get list of providers that currently pass {Prescient::Base#available?}.
    #
    # Providers are included when their health check reports `reachable: true`,
    # or, for legacy adapters, `status == "healthy"`.
    #
    # @return [Array<Symbol>] List of reachable provider names
    def available_providers
      @providers.keys.select do |name|
        provider(name)&.available?
      rescue StandardError
        false
      end
    end
  end

  class << self
    private

    def configure_default_providers(config, env)
      configure_ollama(config, env)
      configure_openai(config, env)
      configure_anthropic(config, env)
      configure_gemini(config, env)
      configure_mistral(config, env)
      configure_deepseek(config, env)
      configure_xai(config, env)
      configure_huggingface(config, env)
    end

    def configure_ollama(config, env)
      config.add_provider(
        :ollama,
        Prescient::Provider::Ollama,
        url:             env.fetch('OLLAMA_URL', 'http://localhost:11434'),
        embedding_model: env.fetch('OLLAMA_EMBEDDING_MODEL', 'nomic-embed-text'),
        chat_model:      env.fetch('OLLAMA_CHAT_MODEL', 'llama3.2:3b'),
      )
    end

    def configure_openai(config, env)
      return unless env['OPENAI_API_KEY']

      config.add_provider(
        :openai,
        Prescient::Provider::OpenAI,
        api_key:         env['OPENAI_API_KEY'],
        embedding_model: env.fetch('OPENAI_EMBEDDING_MODEL', 'text-embedding-3-small'),
        chat_model:      env.fetch('OPENAI_CHAT_MODEL', 'gpt-4.1-mini'),
      )
    end

    def configure_anthropic(config, env)
      return unless env['ANTHROPIC_API_KEY']

      config.add_provider(
        :anthropic,
        Prescient::Provider::Anthropic,
        api_key: env['ANTHROPIC_API_KEY'],
        model:   env.fetch('ANTHROPIC_MODEL', 'claude-sonnet-4-20250514'),
      )
    end

    def configure_gemini(config, env)
      return unless env['GEMINI_API_KEY']

      config.add_provider(
        :gemini,
        Prescient::Provider::Gemini,
        api_key:         env['GEMINI_API_KEY'],
        embedding_model: env.fetch('GEMINI_EMBEDDING_MODEL', 'gemini-embedding-001'),
        chat_model:      env.fetch('GEMINI_CHAT_MODEL', 'gemini-2.5-flash'),
      )
    end

    def configure_huggingface(config, env)
      return unless env['HUGGINGFACE_API_KEY']

      config.add_provider(
        :huggingface,
        Prescient::Provider::HuggingFace,
        api_key:         env['HUGGINGFACE_API_KEY'],
        embedding_model: env.fetch(
          'HUGGINGFACE_EMBEDDING_MODEL',
          'sentence-transformers/all-MiniLM-L6-v2',
        ),
        chat_model:      env.fetch(
          'HUGGINGFACE_CHAT_MODEL',
          'google/gemma-2-2b-it',
        ),
      )
    end

    def configure_deepseek(config, env)
      return unless env['DEEPSEEK_API_KEY']

      config.add_provider(
        :deepseek,
        Prescient::Provider::DeepSeek,
        api_key:    env['DEEPSEEK_API_KEY'],
        chat_model: env.fetch('DEEPSEEK_CHAT_MODEL', 'deepseek-v4-flash'),
      )
    end

    def configure_xai(config, env)
      return unless env['XAI_API_KEY']

      config.add_provider(
        :xai,
        Prescient::Provider::XAI,
        api_key:    env['XAI_API_KEY'],
        chat_model: env.fetch('XAI_CHAT_MODEL', 'grok-4.5'),
      )
    end

    def configure_mistral(config, env)
      return unless env['MISTRAL_API_KEY']

      config.add_provider(
        :mistral,
        Prescient::Provider::Mistral,
        api_key:         env['MISTRAL_API_KEY'],
        embedding_model: env.fetch('MISTRAL_EMBEDDING_MODEL', 'mistral-embed'),
        chat_model:      env.fetch('MISTRAL_CHAT_MODEL', 'mistral-large-latest'),
      )
    end
  end

  # Default configuration
  configure do |config|
    configure_default_providers(config, ENV)
  end
end
