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

  def test_response_errors_exclude_raw_response_bodies
    response = mock('response')
    response.stubs(success?: false, code: 500, body: 'sensitive provider detail')

    error = assert_raises(Prescient::ProviderError) { @provider.send(:validate_response!, response, 'embedding') }

    assert_equal "#{@provider.provider_name} Server Error", error.message
    assert_equal @provider.provider_name, error.provider
    assert_equal 'embedding', error.operation
    assert_equal 500, error.status
    refute_includes error.message, 'sensitive provider detail'
  end

  def test_initialize_calls_validate_configuration
    @test_provider_class.any_instance.expects(:validate_configuration!)
    @test_provider_class.new(api_key: 'test')
  end

  def test_available_returns_true_when_health_check_status_is_healthy
    @provider.stubs(:health_check).returns({ status: 'healthy', reachable: true })

    assert_predicate @provider, :available?
  end

  def test_available_returns_false_when_health_check_status_is_not_healthy
    @provider.stubs(:health_check).returns({ status: 'unhealthy', reachable: false })

    refute_predicate @provider, :available?
  end

  def test_available_returns_false_when_health_check_raises_error
    @provider.stubs(:health_check).raises(StandardError)

    refute_predicate @provider, :available?
  end

  def test_validate_embedding_dimensions_rejects_non_array_embeddings
    error = assert_raises(Prescient::InvalidResponseError) {
      @provider.send(:validate_embedding_dimensions, nil, 5)
    }

    assert_equal 'Embedding response is not an array', error.message
  end

  def test_validate_embedding_dimensions_rejects_non_array_values
    assert_raises(Prescient::InvalidResponseError) do
      @provider.send(:validate_embedding_dimensions, 'not_array', 5)
    end
  end

  def test_validate_embedding_dimensions_returns_exact_vector_unchanged
    embedding = [1, 2, 3, 4, 5]
    result = @provider.send(:validate_embedding_dimensions, embedding, 5)

    assert_same embedding, result
  end

  def test_validate_embedding_dimensions_rejects_longer_vectors
    embedding = [1, 2, 3, 4, 5, 6, 7]
    error = assert_raises(Prescient::InvalidResponseError) {
      @provider.send(:validate_embedding_dimensions, embedding, 5)
    }

    assert_equal 'Invalid embedding dimensions: expected 5, got 7', error.message
  end

  def test_validate_embedding_dimensions_rejects_shorter_vectors
    embedding = [1, 2, 3]
    error = assert_raises(Prescient::InvalidResponseError) {
      @provider.send(:validate_embedding_dimensions, embedding, 5)
    }

    assert_equal 'Invalid embedding dimensions: expected 5, got 3', error.message
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
