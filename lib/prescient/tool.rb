# frozen_string_literal: true

# Namespace for external capability adapters.
module Prescient::Tool
  autoload :SearXNG, 'prescient/tool/searxng'

  # Base contract for explicit external tool invocation.
  class Base
    # @return [Integer] Default request timeout in seconds
    DEFAULT_TIMEOUT = 5
    # @return [Integer] Default maximum number of returned results
    DEFAULT_MAX_RESULTS = 5
    # @return [Integer] Maximum accepted search query length
    MAX_QUERY_LENGTH = 2_000
    # @return [Integer] Maximum accepted tool response size in bytes
    DEFAULT_MAX_RESPONSE_BYTES = 1_048_576

    # @return [Hash<Symbol, untyped>] Tool configuration options
    attr_reader :options

    # @param options [Hash] Tool-specific configuration options
    def initialize(**options)
      @options = options
      validate_configuration!
    end

    # Execute a search using the tool.
    # @param query [String] Search query
    # @param options [Hash] Per-request options
    # @return [Hash] Normalized tool result
    # @raise [NotImplementedError] If the adapter does not support searching
    def search(query, **options)
      raise NotImplementedError, "#{self.class} must implement #search"
    end

    protected

    # Validate adapter configuration.
    # @return [void]
    def validate_configuration!
      # Override in subclasses.
    end

    # @param query [String] Search query
    # @return [String] Validated query
    def validate_query(query)
      unless query.is_a?(String) && !query.strip.empty?
        raise Prescient::ToolConfigurationError, 'search query must be a non-empty string'
      end

      cleaned_query = query.strip
      if cleaned_query.length > MAX_QUERY_LENGTH
        raise Prescient::ToolConfigurationError,
              "search query cannot contain more than #{MAX_QUERY_LENGTH} characters"
      end

      cleaned_query
    end

    # @param value [Object] Requested result limit
    # @return [Integer] Validated result limit
    def result_limit(value)
      limit = value.nil? ? @options.fetch(:max_results, DEFAULT_MAX_RESULTS) : value
      unless limit.is_a?(Integer) && limit.positive?
        raise Prescient::ToolConfigurationError, 'max_results must be a positive integer'
      end

      [limit, 20].min
    end

    # @param value [Object] Requested timeout
    # @return [Numeric] Validated timeout
    def request_timeout(value)
      timeout = value.nil? ? @options.fetch(:timeout, DEFAULT_TIMEOUT) : value
      unless timeout.is_a?(Numeric) && timeout.positive?
        raise Prescient::ToolConfigurationError, 'timeout must be a positive number'
      end

      timeout
    end

    # @return [Integer] Maximum accepted response size
    def max_response_bytes
      value = @options.fetch(:max_response_bytes, DEFAULT_MAX_RESPONSE_BYTES)
      unless value.is_a?(Integer) && value.positive?
        raise Prescient::ToolConfigurationError,
              'max_response_bytes must be a positive integer'
      end

      value
    end
  end
end
