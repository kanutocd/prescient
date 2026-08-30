# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren, Layout/IndentationWidth
module Prescient::MCP
    # Policy and capability configuration for the optional MCP adapter.
    class Configuration
      # @return [Integer] Maximum default MCP input size in bytes
      DEFAULT_MAX_INPUT_BYTES = 64_000
      # @return [Array<String>] Default MCP tools
      DEFAULT_TOOLS = [
        'prescient_generate', 'prescient_embed', 'prescient_providers', 'prescient_health', 'prescient_agent'
      ].freeze
      # @return [Array<String>] Resources supported by the adapter
      SUPPORTED_RESOURCES = ['prescient://providers', 'prescient://health'].freeze

      attr_reader :name
      attr_reader :version
      attr_reader :max_input_bytes
      attr_reader :tools
      attr_reader :resources

      def initialize(name: 'prescient', version: Prescient::VERSION,
                     max_input_bytes: DEFAULT_MAX_INPUT_BYTES,
                     tools: DEFAULT_TOOLS,
                     resources: ['prescient://providers', 'prescient://health'])
        @name = name
        @version = version
        @max_input_bytes = validate_limit(max_input_bytes)
        @tools = Array(tools).map(&:to_s).freeze
        @resources = Array(resources).map(&:to_s).freeze
      end

      private

      def validate_limit(value)
        return value if value.is_a?(Integer) && value.positive?

        raise ArgumentError, 'max_input_bytes must be a positive integer'
      end
    end
end
# rubocop:enable Style/ClassAndModuleChildren, Layout/IndentationWidth
