# frozen_string_literal: true

require 'httparty'
require 'net/http'
require 'timeout'
require 'uri'

# SearXNG web-search tool adapter.
class Prescient::Tool::SearXNG < Prescient::Tool::Base
  # Network failures that should be reported as connection errors.
  NETWORK_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, SocketError, Errno::ECONNREFUSED].freeze

  # @param options [Hash] SearXNG configuration options
  # @option options [String] :url SearXNG base URL
  # @option options [String] :language Optional search language
  # @option options [String, Array<String>] :categories Optional categories
  def initialize(**options)
    super
    @base_url = normalized_base_url(options.fetch(:url))
  end

  # Search SearXNG and return normalized result metadata.
  # @param query [String] Search query
  # @param limit [Integer, nil] Maximum number of results
  # @param timeout [Numeric, nil] Request timeout in seconds
  # @return [Hash] Normalized search result envelope
  def search(query, limit: nil, timeout: nil)
    normalized_query = validate_query(query)
    requested_limit = result_limit(limit)
    requested_timeout = request_timeout(timeout)
    response = HTTParty.get(
      search_url,
      query:   request_parameters(normalized_query),
      timeout: requested_timeout,
    )
    validate_response!(response)

    {
      tool:    'web_search',
      query:   normalized_query,
      source:  'searxng',
      results: normalize_results(response.parsed_response, requested_limit),
    }
  rescue Prescient::Error
    raise
  rescue *NETWORK_ERRORS => e
    raise Prescient::ToolConnectionError, "SearXNG request failed: #{e.class}"
  rescue StandardError => e
    raise Prescient::ToolError, "SearXNG request failed: #{e.message}"
  end

  protected

  # Validate SearXNG-specific configuration.
  # @return [void]
  def validate_configuration!
    normalized_base_url(@options.fetch(:url))
    max_response_bytes
    result_limit(nil)
    request_timeout(nil)
  rescue KeyError
    raise Prescient::ToolConfigurationError, 'SearXNG requires a url'
  end

  private

  def normalized_base_url(value)
    uri = URI.parse(value.to_s)
    valid_scheme = ['http', 'https'].include?(uri.scheme)
    if !valid_scheme || uri.host.nil? || uri.userinfo
      raise Prescient::ToolConfigurationError, 'SearXNG url must be an HTTP(S) URL without credentials'
    end

    uri.to_s.delete_suffix('/')
  rescue URI::InvalidURIError
    raise Prescient::ToolConfigurationError, 'SearXNG url must be a valid HTTP(S) URL'
  end

  def search_url
    "#{@base_url}/search"
  end

  def request_parameters(query)
    parameters = { q: query, format: 'json' }
    parameters[:language] = @options[:language] if @options[:language]
    parameters[:categories] = Array(@options[:categories]).join(',') if @options[:categories]
    parameters
  end

  def validate_response!(response)
    if response.respond_to?(:body) && response.body.to_s.bytesize > max_response_bytes
      raise Prescient::ToolInvalidResponseError, 'SearXNG response exceeds configured size limit'
    end

    return if response.success?

    error_class = case response.code.to_i
                  when 401, 403 then Prescient::AuthenticationError
                  when 429 then Prescient::RateLimitError
                  when 500..599 then Prescient::ToolConnectionError
                  else Prescient::ToolError
                  end
    raise error_class, "SearXNG returned HTTP #{response.code}"
  end

  def normalize_results(payload, limit)
    raw_results = payload.is_a?(Hash) ? payload['results'] : nil
    unless raw_results.is_a?(Array)
      raise Prescient::ToolInvalidResponseError, 'SearXNG response did not contain results'
    end

    raw_results.filter_map { |result|
      next unless result.is_a?(Hash)
      next unless result['url'].is_a?(String) && !result['url'].empty?

      {
        title:   result['title'].to_s,
        url:     result['url'],
        snippet: result['content'].to_s,
        source:  'searxng',
      }
    }.first(limit)
  end
end
