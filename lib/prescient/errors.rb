# frozen_string_literal: true

module Prescient
  # Base error class for all Prescient-specific errors
  class Error < StandardError
    attr_reader :provider
    attr_reader :operation
    attr_reader :status

    def initialize(message = nil, provider: nil, operation: nil, status: nil)
      super(message)

      @provider = provider
      @operation = operation
      @status = status
    end
  end

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

  # Raised when a vector cannot be stored or searched safely
  class InvalidVectorError < Error; end

  # Raised when an AI provider reports a transient service-side failure
  class ProviderError < Error; end

  # Container module for AI provider implementations
  #
  # All provider classes should be defined within this module and inherit
  # from {Prescient::Base}.
  module Provider
    # Module for AI provider implementations
  end

  # Namespace for optional PostgreSQL pgvector integration
  module Pgvector
  end
end
