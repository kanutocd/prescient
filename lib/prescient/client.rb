# frozen_string_literal: true

module Prescient
  # Client class for interacting with AI providers
  #
  # The Client provides a high-level interface for working with AI providers,
  # handling error recovery, retries, and method delegation. It acts as a
  # facade over the configured providers.
  #
  # @example Basic usage
  #   client = Prescient::Client.new(:openai)
  #   response = client.generate_response("Hello, world!")
  #   embedding = client.generate_embedding("Text to embed")
  #
  # @example Using default provider
  #   client = Prescient::Client.new  # Uses configured default
  #   puts client.provider_name       # => :ollama (or configured default)
  #
  # @author Claude Code
  # @since 1.0.0
  class Client
    # @return [Symbol] The name of the provider being used
    attr_reader :provider_name

    # @return [Base] The underlying provider instance
    attr_reader :provider

    # Initialize a new client with the specified provider
    #
    # @param provider_name [Symbol, nil] Name of provider to use, or nil for default
    # @raise [Prescient::Error] If the specified provider is not configured
    def initialize(provider_name = nil)
      @provider_name = provider_name || Prescient.configuration.default_provider
      @provider = Prescient.configuration.provider(@provider_name)

      raise Prescient::Error, "Provider not found: #{@provider_name}" unless @provider
    end

    # Generate embeddings for the given text
    #
    # Delegates to the underlying provider with automatic retry logic
    # for transient failures.
    #
    # @param text [String] The text to generate embeddings for
    # @param options [Hash] Provider-specific options
    # @return [Array<Float>] Array of embedding values
    # @raise [Prescient::Error] If embedding generation fails
    def generate_embedding(text, **options)
      with_error_handling do
        @provider.generate_embedding(text, **options)
      end
    end

    # Generate text response for the given prompt
    #
    # Delegates to the underlying provider with automatic retry logic
    # for transient failures. Supports optional context items for RAG.
    #
    # @param prompt [String] The prompt to generate a response for
    # @param context_items [Array<Hash, String>] Optional context items
    # @param options [Hash] Provider-specific generation options
    # @option options [Float] :temperature Sampling temperature (0.0-2.0)
    # @option options [Integer] :max_tokens Maximum tokens to generate
    # @option options [Float] :top_p Nucleus sampling parameter
    # @return [Hash] Response hash with :response, :model, :provider keys
    # @raise [Prescient::Error] If response generation fails
    def generate_response(prompt, context_items = [], **options)
      with_error_handling do
        @provider.generate_response(prompt, context_items, **options)
      end
    end

    # Check the health status of the provider
    #
    # @return [Hash] Health status information
    def health_check
      @provider.health_check
    end

    # Check if the provider is currently available
    #
    # @return [Boolean] true if provider is healthy and available
    def available?
      @provider.available?
    end

    # Get comprehensive information about the provider
    #
    # Returns details about the provider including its availability
    # and configuration options (with sensitive data removed).
    #
    # @return [Hash] Provider information including :name, :class, :available, :options
    def provider_info
      {
        name:      @provider_name,
        class:     @provider.class.name.split('::').last,
        available: available?,
        options:   sanitize_options(@provider.options),
      }
    end

    def method_missing(method_name, ...)
      @provider.respond_to?(method_name) ? @provider.send(method_name, ...) : super
    end

    def respond_to_missing?(method_name, include_private = false)
      @provider.respond_to?(method_name, include_private) || super
    end

    private

    # TODO: configurable keys to sanitize
    def sanitize_options(options)
      sensitive_keys = [:api_key, :password, :token, :secret]
      options.reject { |key, _| sensitive_keys.include?(key.to_sym) }
    end

    def with_error_handling
      retries = 0
      begin
        yield
      rescue Prescient::RateLimitError => e
        raise e unless retries < Prescient.configuration.retry_attempts

        retries += 1
        sleep(Prescient.configuration.retry_delay * retries)
        retry
      rescue Prescient::ConnectionError => e
        raise e unless retries < Prescient.configuration.retry_attempts

        retries += 1
        sleep(Prescient.configuration.retry_delay)
        retry
      end
    end
  end

  # Convenience methods for quick access
  def self.client(provider_name = nil)
    Client.new(provider_name)
  end

  def self.generate_embedding(text, provider: nil, **options)
    client(provider).generate_embedding(text, **options)
  end

  def self.generate_response(prompt, context_items = [], provider: nil, **options)
    client(provider).generate_response(prompt, context_items, **options)
  end

  def self.health_check(provider: nil)
    client(provider).health_check
  end
end
