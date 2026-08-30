# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::Agent
  # Converts provider and tool failures into bounded, safe agent data.
  class ErrorSerializer
    # @return [Array<Array<Class, String>>] Provider/tool error categories
    CATEGORY_MAP = [
      [Prescient::AuthenticationError, "authentication_failed"],
      [Prescient::ConnectionError, "provider_unavailable"],
      [Prescient::RateLimitError, "rate_limited"],
      [Prescient::ModelNotAvailableError, "model_unavailable"],
      [Prescient::InvalidResponseError, "invalid_provider_response"],
      [Prescient::ProviderError, "provider_failure"],
      [Prescient::ToolConfigurationError, "tool_configuration_error"],
      [Prescient::ToolConnectionError, "tool_unavailable"],
      [Prescient::ToolInvalidResponseError, "invalid_tool_response"],
      [Prescient::ToolError, "tool_failure"]
    ].freeze

    class << self
      # @param error [Exception] Failure to serialize
      # @return [Hash] Safe error envelope
      def serialize(error)
        {
          error: {
            category: category_for(error),
            message: safe_message(error)
          }
        }
      end

      private

      def category_for(error)
        CATEGORY_MAP.find { |error_class, _category| error.is_a?(error_class) }&.last || "internal_failure"
      end

      def safe_message(error)
        return "The requested operation failed." unless error.is_a?(Prescient::Agent::Error)

        error.message.to_s.byteslice(0, 512)
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
