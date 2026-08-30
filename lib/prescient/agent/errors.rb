# frozen_string_literal: true

module Prescient
  module Agent
    # Base error for agent-specific failures.
    class Error < Prescient::Error
    end

    # Raised for invalid agent configuration.
    class ConfigurationError < Error
    end

    # Raised when a provider response contains an invalid action.
    class MalformedActionError < Error
    end

    # Raised when a model requests an unavailable tool.
    class UnauthorizedToolError < Error
    end

    # Raised when execution reaches its configured loop limit.
    class MaxLoopsExceededError < Error
    end
  end
end
