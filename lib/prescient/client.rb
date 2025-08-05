# frozen_string_literal: true

module Prescient
  class Client
    attr_reader :provider_name
    attr_reader :provider

    def initialize(provider_name = nil)
      @provider_name = provider_name || Prescient.configuration.default_provider
      @provider = Prescient.configuration.provider(@provider_name)

      raise Prescient::Error, "Provider not found: #{@provider_name}" unless @provider
    end

    def generate_embedding(text, **options)
      with_error_handling do
        if options.any?
          @provider.generate_embedding(text, **options)
        else
          @provider.generate_embedding(text)
        end
      end
    end

    def generate_response(prompt, context_items = [], **options)
      with_error_handling do
        if options.any?
          @provider.generate_response(prompt, context_items, **options)
        else
          @provider.generate_response(prompt, context_items)
        end
      end
    end

    def health_check
      @provider.health_check
    end

    def available?
      @provider.available?
    end

    def provider_info
      {
        name:      @provider_name,
        class:     @provider.class.name.split('::').last,
        available: available?,
        options:   sanitize_options(@provider.options),
      }
    end

    def method_missing(method_name, ...)
      if @provider.respond_to?(method_name)
        @provider.send(method_name, ...)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      @provider.respond_to?(method_name, include_private) || super
    end

    private

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
