# frozen_string_literal: true

require 'test_helper'

class BaseTest < PrescientTest
  def setup
    super
    @test_provider_class = Class.new(Prescient::Base) do
      def generate_embedding(_text, **_options)
        [1, 2, 3]
      end

      def generate_response(prompt, _context_items = [], **_options)
        { response: "Test response to: #{prompt}" }
      end

      def health_check
        { status: 'healthy' }
      end
    end
    @provider = @test_provider_class.new(api_key: 'test')
  end

  def test_initialize_stores_options
    assert_equal 'test', @provider.options[:api_key]
  end

  def test_initialize_calls_validate_configuration
    @test_provider_class.any_instance.expects(:validate_configuration!)
    @test_provider_class.new(api_key: 'test')
  end

  def test_available_returns_true_when_health_check_status_is_healthy
    @provider.stubs(:health_check).returns({ status: 'healthy' })

    assert_predicate @provider, :available?
  end

  def test_available_returns_false_when_health_check_status_is_not_healthy
    @provider.stubs(:health_check).returns({ status: 'unhealthy' })

    refute_predicate @provider, :available?
  end

  def test_available_returns_false_when_health_check_raises_error
    @provider.stubs(:health_check).raises(StandardError)

    refute_predicate @provider, :available?
  end

  def test_normalize_embedding_returns_nil_for_nil_embedding
    result = @provider.send(:normalize_embedding, nil, 5)

    assert_nil result
  end

  def test_normalize_embedding_returns_nil_for_non_array_embedding
    result = @provider.send(:normalize_embedding, 'not_array', 5)

    assert_nil result
  end

  def test_normalize_embedding_returns_embedding_unchanged_when_length_matches_target
    embedding = [1, 2, 3, 4, 5]
    result = @provider.send(:normalize_embedding, embedding, 5)

    assert_equal [1, 2, 3, 4, 5], result
  end

  def test_normalize_embedding_truncates_embedding_when_longer_than_target
    embedding = [1, 2, 3, 4, 5, 6, 7]
    result = @provider.send(:normalize_embedding, embedding, 5)

    assert_equal [1, 2, 3, 4, 5], result
  end

  def test_normalize_embedding_pads_embedding_with_zeros_when_shorter_than_target
    embedding = [1, 2, 3]
    result = @provider.send(:normalize_embedding, embedding, 5)

    assert_equal [1, 2, 3, 0.0, 0.0], result
  end

  def test_clean_text_returns_empty_string_for_blank_text
    assert_equal '', @provider.send(:clean_text, nil)
    assert_equal '', @provider.send(:clean_text, '')
    assert_equal '', @provider.send(:clean_text, '   ')
  end

  def test_clean_text_normalizes_whitespace
    text = "  Multiple   spaces\n\nand\tlines  "
    result = @provider.send(:clean_text, text)

    assert_equal 'Multiple spaces and lines', result
  end

  def test_clean_text_limits_text_length
    long_text = 'a' * 10000
    result = @provider.send(:clean_text, long_text)

    assert_equal 8000, result.length
  end

  def test_clean_text_converts_to_string
    result = @provider.send(:clean_text, 12345)

    assert_equal '12345', result
  end

  def test_handle_errors_yields_block_when_no_errors
    result = @provider.send(:handle_errors) { 'success' }

    assert_equal 'success', result
  end

  def test_handle_errors_converts_net_read_timeout_to_connection_error
    error = assert_raises(Prescient::ConnectionError) {
      @provider.send(:handle_errors) { raise Net::ReadTimeout }
    }
    assert_match(/Request timeout/, error.message)
  end

  def test_handle_errors_converts_net_open_timeout_to_connection_error
    error = assert_raises(Prescient::ConnectionError) {
      @provider.send(:handle_errors) { raise Net::OpenTimeout }
    }
    assert_match(/Request timeout/, error.message)
  end

  def test_handle_errors_converts_json_parser_error_to_invalid_response_error
    error = assert_raises(Prescient::InvalidResponseError) {
      @provider.send(:handle_errors) { raise JSON::ParserError }
    }
    assert_match(/Invalid JSON response/, error.message)
  end

  def test_handle_errors_converts_other_standard_error_to_generic_error
    error = assert_raises(Prescient::Error) {
      @provider.send(:handle_errors) { raise StandardError, 'test error' }
    }
    assert_match(/Unexpected error: test error/, error.message)
  end
end
