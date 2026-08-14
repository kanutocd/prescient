# frozen_string_literal: true

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
