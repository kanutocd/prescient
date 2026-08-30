# frozen_string_literal: true

require "httparty"
require "net/http"
require "timeout"

module Prescient
  module Tool
    # SearchApi web-search tool adapter.
    class SearchApi < Prescient::Tool::Base
      # SearchApi's stable search endpoint.
      API_URL = "https://www.searchapi.io/api/v1/search"
      # Network failures that should be reported as connection errors.
      NETWORK_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, SocketError,
                        Errno::ECONNREFUSED].freeze

      # @param options [Hash] SearchApi configuration options
      # @option options [String] :api_key SearchApi API key
      # @option options [String] :engine SearchApi engine, defaulting to Google
      # @option options [String] :location Optional search location
      # @option options [String] :hl Optional interface language
      # @option options [String] :gl Optional country code
      def initialize(**options)
        super
        @api_key = required_api_key(options[:api_key])
      end

      # Search SearchApi and return normalized result metadata.
      # @param query [String] Search query
      # @param limit [Integer, nil] Maximum number of results
      # @param timeout [Numeric, nil] Request timeout in seconds
      # @return [Hash] Normalized search result envelope
      def search(query, limit: nil, timeout: nil)
        normalized_query = validate_query(query)
        requested_limit = result_limit(limit)
        requested_timeout = request_timeout(timeout)
        response = HTTParty.get(
          API_URL,
          headers: request_headers,
          query: request_parameters(normalized_query, requested_limit),
          timeout: requested_timeout
        )
        validate_response!(response)

        {
          tool: "web_search",
          query: normalized_query,
          source: "searchapi",
          results: normalize_results(response.parsed_response, requested_limit)
        }
      rescue Prescient::Error
        raise
      rescue *NETWORK_ERRORS => e
        raise Prescient::ToolConnectionError, "SearchApi request failed: #{e.class}"
      rescue StandardError => e
        raise Prescient::ToolError, "SearchApi request failed: #{e.message}"
      end

      protected

      # Validate SearchApi-specific configuration.
      # @return [void]
      def validate_configuration!
        required_api_key(@options[:api_key])
        max_response_bytes
        result_limit(nil)
        request_timeout(nil)
      end

      private

      def required_api_key(value)
        return value if value.is_a?(String) && !value.empty?

        raise Prescient::ToolConfigurationError, "SearchApi requires an api_key"
      end

      def request_headers
        { "Authorization" => "Bearer #{@api_key}" }
      end

      def request_parameters(query, limit)
        parameters = {
          engine: @options.fetch(:engine, "google"),
          q: query,
          num: limit
        }
        %i[location hl gl].each do |key|
          parameters[key] = @options[key] if @options[key]
        end
        parameters
      end

      def validate_response!(response)
        if response.respond_to?(:body) && response.body.to_s.bytesize > max_response_bytes
          raise Prescient::ToolInvalidResponseError, "SearchApi response exceeds configured size limit"
        end

        return if response.success?

        error_class = case response.code.to_i
                      when 401, 403 then Prescient::AuthenticationError
                      when 429 then Prescient::RateLimitError
                      when 500..599 then Prescient::ToolConnectionError
                      else Prescient::ToolError
                      end
        raise error_class, "SearchApi returned HTTP #{response.code}"
      end

      def normalize_results(payload, limit)
        raw_results = payload.is_a?(Hash) ? payload["organic_results"] : nil
        unless raw_results.is_a?(Array)
          raise Prescient::ToolInvalidResponseError, "SearchApi response did not contain organic_results"
        end

        raw_results.filter_map do |result|
          next unless result.is_a?(Hash)
          next unless result["link"].is_a?(String) && !result["link"].empty?

          {
            title: result["title"].to_s,
            url: result["link"],
            snippet: result["snippet"].to_s,
            source: "searchapi"
          }
        end.first(limit)
      end
    end
  end
end
