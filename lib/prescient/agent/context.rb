# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::Agent
  # Per-run, bounded conversation history rendered as provider context.
  class Context
    attr_reader :messages

    def initialize(system_prompt:, task:, max_bytes: Configuration::DEFAULT_MAX_CONTEXT_BYTES)
      @max_bytes = max_bytes
      @messages = [
        { role: 'system', content: system_prompt },
        { role: 'user', content: task },
      ]
      enforce_limit!
    end

    # Append a bounded turn to the run history.
    # @param role [String] Message role
    # @param content [String] Message content
    # @return [void]
    def append(role:, content:)
      @messages << { role: role, content: content.to_s }
      enforce_limit!
    end

    # Return a copy of the provider-compatible history.
    # @return [Array<Hash>]
    def to_a
      @messages.map(&:dup)
    end

    private

    def enforce_limit!
      return if serialized_bytes <= @max_bytes

      raise Prescient::Agent::ConfigurationError, 'agent context exceeds configured size limit'
    end

    def serialized_bytes
      JSON.generate(@messages).bytesize
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
