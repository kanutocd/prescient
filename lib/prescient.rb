# frozen_string_literal: true

require_relative 'prescient/version'

module Prescient
  class Error < StandardError; end
  class ConnectionError < Error; end
  class AuthenticationError < Error; end
  class RateLimitError < Error; end
  class ModelNotAvailableError < Error; end
  class InvalidResponseError < Error; end

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
  # Configure the gem
  def self.configure
    yield(configuration)
  end

  def self.configuration
    @_configuration ||= Configuration.new
  end

  def self.reset_configuration!
    @_configuration = Configuration.new
  end

  class Configuration
    attr_accessor :default_provider
    attr_accessor :timeout
    attr_accessor :retry_attempts
    attr_accessor :retry_delay
    attr_reader :providers

    def initialize
      @default_provider = :ollama
      @timeout = 30
      @retry_attempts = 3
      @retry_delay = 1.0
      @providers = {}
    end

    def add_provider(name, provider_class, **options)
      @providers[name.to_sym] = {
        class:   provider_class,
        options: options,
      }
    end

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
