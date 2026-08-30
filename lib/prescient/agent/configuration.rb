# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::Agent
  # Runtime policies and safety limits for one agent execution.
  class Configuration
    # @return [Integer] Default maximum loop count
    DEFAULT_MAX_LOOPS = 5
    # @return [Integer] Default context size limit
    DEFAULT_MAX_CONTEXT_BYTES = 64_000
    # @return [Integer] Default action size limit
    DEFAULT_MAX_ACTION_BYTES = 8_192
    # @return [Integer] Default observation size limit
    DEFAULT_MAX_OBSERVATION_BYTES = 16_384

    attr_reader :max_loops
    attr_reader :max_context_bytes
    attr_reader :max_action_bytes
    attr_reader :max_observation_bytes
    attr_reader :authorization
    attr_reader :telemetry

    def initialize(max_loops: DEFAULT_MAX_LOOPS, max_context_bytes: DEFAULT_MAX_CONTEXT_BYTES,
                   max_action_bytes: DEFAULT_MAX_ACTION_BYTES,
                   max_observation_bytes: DEFAULT_MAX_OBSERVATION_BYTES,
                   authorization: nil, telemetry: nil)
      @max_loops = positive_integer(max_loops, 'max_loops')
      @max_context_bytes = positive_integer(max_context_bytes, 'max_context_bytes')
      @max_action_bytes = positive_integer(max_action_bytes, 'max_action_bytes')
      @max_observation_bytes = positive_integer(max_observation_bytes, 'max_observation_bytes')
      @authorization = callable_or_nil(authorization, 'authorization')
      @telemetry = callable_or_nil(telemetry, 'telemetry')
    end

    private

    def positive_integer(value, name)
      return value if value.is_a?(Integer) && value.positive?

      raise Prescient::Agent::ConfigurationError, "#{name} must be a positive integer"
    end

    def callable_or_nil(value, name)
      return value if value.nil? || value.respond_to?(:call)

      raise Prescient::Agent::ConfigurationError, "#{name} must respond to call"
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
