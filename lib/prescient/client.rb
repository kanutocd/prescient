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
  class Client
    # @return [Symbol] The name of the provider being used
    attr_reader :provider_name

    # @return [Prescient::Base] The underlying provider instance
    attr_reader :provider

    # Initialize a new client with the specified provider
    #
    # @param provider_name [Symbol, nil] Name of provider to use, or nil for default
    # @param enable_fallback [Boolean] Whether to enable automatic fallback to other providers
    # @raise [Prescient::Error] If the specified provider is not configured
    def initialize(provider_name = nil, enable_fallback: true)
      @provider_name = provider_name || Prescient.configuration.default_provider
      @provider = Prescient.configuration.provider(@provider_name)
      @enable_fallback = enable_fallback

      raise Prescient::Error, "Provider not configured: #{@provider_name}" unless @provider
    end

    # Generate embeddings for the given text
    #
    # Delegates to the underlying provider with automatic retry logic
    # for transient failures. If fallback is enabled, tries other providers
    # on persistent failures.
    #
    # @param text [String] The text to generate embeddings for
    # @param options [Hash] Provider-specific options
    # @return [Array<Float>] Array of embedding values
    # @raise [Prescient::Error] If embedding generation fails on all providers
    def generate_embedding(text, **options)
      if @enable_fallback
        with_fallback_handling(:generate_embedding, text, **options)
      else
        with_error_handling do
          @provider.generate_embedding(text, **options)
        end
      end
    end

    # Generate text response for the given prompt
    #
    # Delegates to the underlying provider with automatic retry logic
    # for transient failures. Supports optional context items for RAG.
    # If fallback is enabled, tries other providers on persistent failures.
    #
    # @param prompt [String] The prompt to generate a response for
    # @param context_items [Array<Hash, String>] Optional context items
    # @param options [Hash] Provider-specific generation options
    # @option options [Float] :temperature Sampling temperature (0.0-2.0)
    # @option options [Integer] :max_tokens Maximum tokens to generate
    # @option options [Float] :top_p Nucleus sampling parameter
    # @return [Hash] Response hash with :response, :model, :provider keys
    # @raise [Prescient::Error] If response generation fails on all providers
    def generate_response(prompt, context_items = [], **options)
      if @enable_fallback
        with_fallback_handling(:generate_response, prompt, context_items, **options)
      else
        with_error_handling do
          @provider.generate_response(prompt, context_items, **options)
        end
      end
    end

    # Check the health status of the provider
    #
    # @return [Hash] Health status information from the selected provider
    def health_check
      @provider.health_check
    end

    # Check if the provider is currently available
    #
    # @return [Boolean] true if the provider currently passes its availability check
    def available?
      @provider.available?
    end

    # Get comprehensive information about the provider
    #
    # Returns details about the provider including its availability
    # and configuration options (with sensitive data removed).
    #
    # @return [Hash] Provider information including :name, :class, :available,
    #   and recursively sanitized :options
    def provider_info
      {
        name:      @provider_name,
        class:     @provider.class.name.split('::').last,
        available: available?,
        options:   sanitize_options(@provider.options),
      }
    end

    private

    def sanitize_options(options)
      sensitive_keys = Prescient::Configuration::DEFAULT_SENSITIVE_KEYS + Prescient.configuration.sensitive_keys

      case options
      when Hash
        sanitized = {} # : Hash[untyped, untyped]
        options.each do |key, value|
          next if key.respond_to?(:to_sym) && sensitive_keys.include?(key.to_sym)

          sanitized[key] = sanitize_options(value)
        end
        sanitized
      when Array
        options.map { |value| sanitize_options(value) }
      else
        options
      end
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

    def with_fallback_handling(method_name, *args, **options)
      last_error = nil

      providers_to_try.each_with_index do |provider_name, index|
        provider = provider_for(provider_name, index)
        next unless provider

        # Check if provider is available before trying
        next unless provider.available?

        # Use retry logic for each provider
        return with_error_handling do
          provider.send(method_name, *args, **options)
        end
      rescue Prescient::Error => e
        raise e unless fallback_eligible?(e)

        last_error = e
        next
      end

      # If we get here, all providers failed
      raise last_error || Prescient::Error.new("No available providers for #{method_name}")
    end

    def provider_for(provider_name, index)
      return @provider if index.zero? && provider_name == @provider_name

      Prescient.configuration.provider(provider_name)
    end

    def providers_to_try
      providers = [@provider_name]

      # Add configured fallback providers
      fallback_providers = Prescient.configuration.fallback_providers
      additional_providers = if fallback_providers && !fallback_providers.empty?
                               fallback_providers.reject { |p| p == @provider_name }
                             else
                               # If no explicit fallbacks are configured, probe all configured providers
                               Prescient.configuration.providers.keys.reject { |p| p == @provider_name }
                             end
      providers += additional_providers

      providers.uniq
    end

    def fallback_eligible?(error)
      [
        Prescient::ConnectionError,
        Prescient::RateLimitError,
        Prescient::ModelNotAvailableError,
        Prescient::ProviderError,
      ].any? { |error_class| error.is_a?(error_class) }
    end
  end

  # Convenience methods for quick access
  #
  # @param provider_name [Symbol, nil] Provider to use, or the configured default
  # @param enable_fallback [Boolean] Whether provider fallback is enabled
  # @return [Client] A configured client instance
  def self.client(provider_name = nil, enable_fallback: true)
    Client.new(provider_name, enable_fallback: enable_fallback)
  end

  # Generate an embedding through a configured provider.
  #
  # @param text [String] Text to embed
  # @param provider [Symbol, nil] Provider to use
  # @param enable_fallback [Boolean] Whether provider fallback is enabled
  # @return [Array<Float>] Embedding vector
  def self.generate_embedding(text, provider: nil, enable_fallback: true, **options)
    client(provider, enable_fallback: enable_fallback).generate_embedding(text, **options)
  end

  # Generate a response through a configured provider.
  #
  # @param prompt [String] Prompt to send
  # @param context_items [Array<Hash, String>] Optional context items
  # @param provider [Symbol, nil] Provider to use
  # @param enable_fallback [Boolean] Whether provider fallback is enabled
  # @return [Hash] Normalized provider response with :response, :model, :provider
  #   and optional metadata
  def self.generate_response(prompt, context_items = [], provider: nil, enable_fallback: true, **options)
    client(provider, enable_fallback: enable_fallback).generate_response(prompt, context_items, **options)
  end

  # Return the health status of a configured provider.
  #
  # @param provider [Symbol, nil] Provider to check
  # @return [Hash] Provider health information
  def self.health_check(provider: nil)
    client(provider, enable_fallback: false).health_check
  end
end
