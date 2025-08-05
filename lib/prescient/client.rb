# frozen_string_literal: true

module Prescient
  class Client
    attr_reader :provider_name
    attr_reader :provider

    def initialize(provider_name = nil)
      @provider_name = provider_name || Prescient.configuration.default_provider
      @provider = Prescient.configuration.provider(@provider_name)

      raise Prescient::Error, "Provider '#{@provider_name}' not configured" unless @provider
    end

    def generate_embedding(text, **options)
      with_error_handling do
        @provider.generate_embedding(text, **options)
      end
    end

    def generate_response(prompt, context_items = [], **options)
      with_error_handling do
        @provider.generate_response(prompt, context_items, **options)
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
        class:     @provider.class.name,
        available: available?,
        options:   @provider.options.except(:api_key), # Hide sensitive data
      }
    end

    private

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
