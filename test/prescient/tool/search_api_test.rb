# frozen_string_literal: true

require 'test_helper'

# rubocop:disable Layout/HashAlignment, Style/BlockDelimiters, Minitest/EmptyLineBeforeAssertionMethods
class SearchApiToolTest < PrescientTest
  def setup
    super
    @tool = Prescient::Tool::SearchApi.new(
      api_key:           'test-key',
      engine:            'google',
      location:          'New York',
      hl:                'en',
      gl:                'us',
      timeout:           3,
      max_results:       5,
      max_response_bytes: 1000,
    )
  end

  def test_search_normalizes_and_limits_results
    response = stub(
      success?: true,
      body: JSON.generate(organic_results: []),
      parsed_response: {
        'organic_results' => [
          { 'title' => 'First', 'link' => 'https://example.test/1', 'snippet' => 'One' },
          { 'title' => 'Second', 'link' => 'https://example.test/2', 'snippet' => 'Two' },
          { 'title' => 'Ignored' },
        ],
      },
    )
    HTTParty.expects(:get).with(
      Prescient::Tool::SearchApi::API_URL,
      headers: { 'Authorization' => 'Bearer test-key' },
      query: { engine: 'google', q: 'Ruby tools', num: 1, location: 'New York', hl: 'en', gl: 'us' },
      timeout: 3,
    ).returns(response)

    result = @tool.search('  Ruby tools  ', limit: 1)

    assert_equal 'web_search', result[:tool]
    assert_equal 'Ruby tools', result[:query]
    assert_equal 'searchapi', result[:source]
    assert_equal [{ title: 'First', url: 'https://example.test/1', snippet: 'One', source: 'searchapi' }],
                 result[:results]
  end

  def test_search_rejects_invalid_queries_and_options
    assert_raises(Prescient::ToolConfigurationError) { @tool.search(' ') }
    assert_raises(Prescient::ToolConfigurationError) { @tool.search('x' * 2_001) }
    assert_raises(Prescient::ToolConfigurationError) { @tool.search('query', limit: 0) }
    assert_raises(Prescient::ToolConfigurationError) { @tool.search('query', timeout: 0) }
  end

  def test_initialization_rejects_invalid_configuration
    assert_raises(Prescient::ToolConfigurationError) { Prescient::Tool::SearchApi.new }
    assert_raises(Prescient::ToolConfigurationError) { Prescient::Tool::SearchApi.new(api_key: '') }
    assert_raises(Prescient::ToolConfigurationError) do
      Prescient::Tool::SearchApi.new(api_key: 'key', max_results: 0)
    end
    assert_raises(Prescient::ToolConfigurationError) do
      Prescient::Tool::SearchApi.new(api_key: 'key', timeout: 0)
    end
    assert_raises(Prescient::ToolConfigurationError) do
      Prescient::Tool::SearchApi.new(api_key: 'key', max_response_bytes: 0)
    end
  end

  def test_search_rejects_malformed_and_oversized_results
    response = stub(success?: true, body: '{}', parsed_response: {})
    HTTParty.stubs(:get).returns(response)

    assert_raises(Prescient::ToolInvalidResponseError) { @tool.search('query') }

    response = stub(success?: true, body: '{}', parsed_response: [])
    HTTParty.stubs(:get).returns(response)
    assert_raises(Prescient::ToolInvalidResponseError) { @tool.search('query') }

    response = stub(success?: true, body: '{}', parsed_response: { 'organic_results' => ['invalid', { 'link' => '' }] })
    HTTParty.stubs(:get).returns(response)
    assert_equal [], @tool.search('query')[:results]

    response = stub(success?: true, body: 'x' * 1_001, parsed_response: {})
    HTTParty.stubs(:get).returns(response)
    assert_raises(Prescient::ToolInvalidResponseError) { @tool.search('query') }
  end

  def test_search_supports_default_optional_parameters
    tool = Prescient::Tool::SearchApi.new(api_key: 'test-key')
    response = stub(success?: true, body: '{}', parsed_response: { 'organic_results' => [] })
    HTTParty.expects(:get).with(
      Prescient::Tool::SearchApi::API_URL,
      headers: { 'Authorization' => 'Bearer test-key' },
      query: { engine: 'google', q: 'query', num: 5 },
      timeout: 5,
    ).returns(response)

    assert_empty tool.search('query')[:results]
  end

  def test_search_maps_http_and_connection_failures
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

    HTTParty.stubs(:get).raises(Net::OpenTimeout)
    error = assert_raises(Prescient::ToolConnectionError) { @tool.search('query') }
    assert_equal 'SearchApi request failed: Net::OpenTimeout', error.message

    HTTParty.stubs(:get).raises(RuntimeError, 'unexpected')
    error = assert_raises(Prescient::ToolError) { @tool.search('query') }
    assert_equal 'SearchApi request failed: unexpected', error.message
  end
end
# rubocop:enable Layout/HashAlignment, Style/BlockDelimiters, Minitest/EmptyLineBeforeAssertionMethods
