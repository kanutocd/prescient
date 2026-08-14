# frozen_string_literal: true

require 'test_helper'

# The adapter tests intentionally use compact stubs and option matrices.
# rubocop:disable Layout/HashAlignment, Style/BlockDelimiters, Minitest/EmptyLineBeforeAssertionMethods
class SearXNGToolTest < PrescientTest
  def setup
    super
    @tool = Prescient::Tool::SearXNG.new(
      url:              'http://localhost:8080/',
      language:         'en',
      categories:       ['general', 'news'],
      timeout:          3,
      max_results:      5,
      max_response_bytes: 1000,
    )
  end

  def test_search_normalizes_and_limits_results
    response = stub(
      success?: true,
      body: JSON.generate(results: [
        { 'title' => 'First', 'url' => 'https://example.test/1', 'content' => 'One' },
        { 'title' => 'Second', 'url' => 'https://example.test/2', 'content' => 'Two' },
        { 'title' => 'Ignored', 'content' => 'No URL' },
      ]),
      parsed_response: {
        'results' => [
          { 'title' => 'First', 'url' => 'https://example.test/1', 'content' => 'One' },
          { 'title' => 'Second', 'url' => 'https://example.test/2', 'content' => 'Two' },
          { 'title' => 'Ignored', 'content' => 'No URL' },
        ],
      },
    )
    HTTParty.expects(:get).with(
      'http://localhost:8080/search',
      query: { q: 'Ruby tools', format: 'json', language: 'en', categories: 'general,news' },
      timeout: 3,
    ).returns(response)

    result = @tool.search('  Ruby tools  ', limit: 1)

    assert_equal 'web_search', result[:tool]
    assert_equal 'Ruby tools', result[:query]
    assert_equal 'searxng', result[:source]
    assert_equal [{ title: 'First', url: 'https://example.test/1', snippet: 'One', source: 'searxng' }],
                 result[:results]
  end

  def test_search_rejects_invalid_queries
    assert_raises(Prescient::ToolConfigurationError) { @tool.search(' ') }
    assert_raises(Prescient::ToolConfigurationError) { @tool.search('x' * 2_001) }
  end

  def test_search_rejects_invalid_request_options
    assert_raises(Prescient::ToolConfigurationError) { @tool.search('query', limit: 0) }
    assert_raises(Prescient::ToolConfigurationError) { @tool.search('query', timeout: 0) }
  end

  def test_initialization_rejects_invalid_configuration
    assert_raises(Prescient::ToolConfigurationError) { Prescient::Tool::SearXNG.new }
    assert_raises(Prescient::ToolConfigurationError) { Prescient::Tool::SearXNG.new(url: 'ftp://example.test') }
    assert_raises(Prescient::ToolConfigurationError) do
      Prescient::Tool::SearXNG.new(url: 'http://user:pass@example.test')
    end
    assert_raises(Prescient::ToolConfigurationError) do
      Prescient::Tool::SearXNG.new(url: 'http://example.test', max_results: 0)
    end
    assert_raises(Prescient::ToolConfigurationError) do
      Prescient::Tool::SearXNG.new(url: 'http://example.test', timeout: 0)
    end
    assert_raises(Prescient::ToolConfigurationError) do
      Prescient::Tool::SearXNG.new(url: 'http://example.test', max_response_bytes: 0)
    end
    assert_raises(Prescient::ToolConfigurationError) do
      Prescient::Tool::SearXNG.new(url: 'not a url')
    end
  end

  def test_search_rejects_malformed_results
    response = stub(success?: true, body: '{}', parsed_response: {})
    HTTParty.stubs(:get).returns(response)

    assert_raises(Prescient::ToolInvalidResponseError) { @tool.search('query') }

    response = stub(success?: true, body: '{}', parsed_response: { 'results' => ['invalid', { 'url' => '' }] })
    HTTParty.stubs(:get).returns(response)
    assert_equal [], @tool.search('query')[:results]

    response = stub(success?: true, body: '{}', parsed_response: [])
    HTTParty.stubs(:get).returns(response)
    assert_raises(Prescient::ToolInvalidResponseError) { @tool.search('query') }
  end

  def test_search_supports_default_optional_parameters
    tool = Prescient::Tool::SearXNG.new(url: 'http://localhost:8080')
    response = stub(success?: true, body: '{}', parsed_response: { 'results' => [] })
    HTTParty.expects(:get).with(
      'http://localhost:8080/search',
      query: { q: 'query', format: 'json' },
      timeout: 5,
    ).returns(response)

    assert_empty tool.search('query')[:results]
  end

  def test_search_rejects_oversized_responses
    response = stub(success?: true, body: 'x' * 1_001, parsed_response: {})
    HTTParty.stubs(:get).returns(response)

    assert_raises(Prescient::ToolInvalidResponseError) { @tool.search('query') }
  end

  def test_search_maps_http_failures
    {
      401 => Prescient::AuthenticationError,
      429 => Prescient::RateLimitError,
      503 => Prescient::ToolConnectionError,
      400 => Prescient::ToolError,
    }.each do |status, error_class|
      response = stub(success?: false, body: '', code: status)
      HTTParty.stubs(:get).returns(response)

      assert_raises(error_class) { @tool.search('query') }
    end
  end

  def test_search_maps_connection_failures
    HTTParty.stubs(:get).raises(Net::OpenTimeout)

    error = assert_raises(Prescient::ToolConnectionError) { @tool.search('query') }

    assert_equal 'SearXNG request failed: Net::OpenTimeout', error.message
  end

  def test_base_tool_requires_search_implementation
    tool = Prescient::Tool::Base.new

    assert_raises(NotImplementedError) { tool.search('query') }
  end

  def test_search_wraps_unexpected_failures
    HTTParty.stubs(:get).raises(RuntimeError, 'unexpected')

    error = assert_raises(Prescient::ToolError) { @tool.search('query') }

    assert_equal 'SearXNG request failed: unexpected', error.message
  end
end
# rubocop:enable Layout/HashAlignment, Style/BlockDelimiters, Minitest/EmptyLineBeforeAssertionMethods
