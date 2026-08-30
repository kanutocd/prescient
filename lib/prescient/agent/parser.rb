# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::Agent
  # Extracts and validates one tool action from provider text.
  class Parser
    # @return [Regexp] Fenced JSON action matcher
    ACTION_PATTERN = /```json\s*(\{.*?\})\s*```/m

    # Parse one optional action from provider output.
    # @param text [String] Provider response text
    # @param max_bytes [Integer] Maximum action size
    # @return [Hash, nil] Parsed action or nil for a final response
    def self.parse(text, max_bytes: Configuration::DEFAULT_MAX_ACTION_BYTES)
      new(max_bytes:).parse(text)
    end

    def initialize(max_bytes: Configuration::DEFAULT_MAX_ACTION_BYTES)
      @max_bytes = max_bytes
    end

    # Parse one optional action from provider output.
    # @param text [String] Provider response text
    # @return [Hash, nil] Parsed action or nil for a final response
    def parse(text)
      match = text.to_s.match(ACTION_PATTERN)
      return nil unless match
      raise MalformedActionError, "agent action exceeds configured size limit" if match[1].bytesize > @max_bytes

      payload = JSON.parse(match[1])
      validate_payload(payload)
      { name: payload.fetch("action").to_sym, arguments: payload.fetch("args") }
    rescue JSON::ParserError => e
      raise MalformedActionError, "agent action contains invalid JSON: #{e.message}"
    end

    private

    def validate_payload(payload)
      unless payload.is_a?(Hash) && payload.keys.sort == %w[action args]
        raise MalformedActionError, "agent action must contain only action and args"
      end
      return if payload["action"].is_a?(String) && !payload["action"].empty? && payload["args"].is_a?(Hash)

      raise MalformedActionError, "agent action must define a name and object args"
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
