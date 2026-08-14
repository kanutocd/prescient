# frozen_string_literal: true

require 'test_helper'

class CoverageGapTest < PrescientTest
  def setup
    super
    @base = Prescient::Base.new
  end

  def test_base_abstract_methods_raise
    assert_raises(NotImplementedError) do
      @base.generate_embedding('text')
    end
    assert_raises(NotImplementedError) do
      @base.generate_response('prompt')
    end
    assert_raises(NotImplementedError) { @base.health_check }
  end

  def test_base_wraps_net_http_errors
    error = assert_raises(Prescient::ConnectionError) {
      @base.send(:handle_errors) { raise Net::HTTPError.new('http error', nil) }
    }

    assert_includes error.message, 'HTTP error'
  end

  def test_base_extracts_embedding_text_from_scalars_and_hashes
    assert_equal '123', @base.send(:extract_embedding_text, 123)
    assert_equal 'Title body 42', @base.send(:extract_embedding_text,
                                             'title' => 'Title', 'body' => 'body', 'count' => 42,
                                             'id' => 7, 'blank' => ' ', 'object' => Object.new)
  end

  def test_base_extracts_configured_embedding_fields
    provider = Prescient::Base.new(
      context_configs: {
        'article' => {
          fields: ['title', 'body'], format: nil, embedding_fields: ['title', 'body']
        },
      },
    )

    assert_equal 'Title Body', provider.send(:extract_embedding_text,
                                             { :title => 'Title', 'body' => 'Body' }, 'article')
  end

  def test_base_formats_context_item_variants
    assert_equal 'plain', @base.send(:format_context_item, 'plain')
    assert_equal '12', @base.send(:format_context_item, 12)
    assert_equal 'a: b', @base.send(:format_context_item, 'a' => 'b')
  end

  def test_base_formats_configured_context_and_falls_back_for_missing_data
    provider = Prescient::Base.new(
      context_configs: {
        'article' => {
          fields: ['title', 'author'], format: '%<title>s by %<author>s', embedding_fields: []
        },
      },
    )

    assert_equal 'Title by Author', provider.send(:format_context_item,
                                                  { 'type' => 'article', 'title' => 'Title', 'author' => 'Author' })
    assert_equal 'type: article', provider.send(:format_context_item, 'type' => 'article')

    malformed = Prescient::Base.new(
      context_configs: {
        'article' => { fields: ['title'], format: '%<missing>s', embedding_fields: [] },
      },
    )

    assert_equal 'type: article, title: Title', malformed.send(
      :format_context_item, 'type' => 'article', 'title' => 'Title'
    )
  end

  def test_base_detects_explicit_and_field_matched_context_types
    provider = Prescient::Base.new(
      context_configs: {
        'article' => { fields: ['title', 'body'], format: nil, embedding_fields: [] },
        'person'  => { fields: ['name', 'email'], format: nil, embedding_fields: [] },
      },
    )

    assert_equal 'article', provider.send(:detect_context_type, 'type' => 'article', 'title' => 'T')
    assert_equal 'context', provider.send(:detect_context_type, 'context_type' => 'context', 'name' => 'N')
    assert_equal 'article', provider.send(:detect_context_type, 'model_type' => 'ARTICLE', 'title' => 'T')
    assert_equal 'article', provider.send(:detect_context_type, 'title' => 'T', 'body' => 'B')
    assert_equal 'title: T, body: B', provider.send(:format_context_item, 'title' => 'T', 'body' => 'B')
    assert_equal 'other: value', provider.send(:format_context_item, 'other' => 'value')
  end

  def test_base_context_matching_handles_empty_and_partial_configurations
    provider = Prescient::Base.new(
      context_configs: {
        'empty'   => { fields: [], format: nil, embedding_fields: [] },
        'article' => { fields: ['title', 'body'], format: nil, embedding_fields: [] },
      },
    )

    assert_equal '', provider.send(:format_context_item, {})
    assert_equal 'title: T', provider.send(:format_context_item, 'title' => 'T')
    assert_equal 'unrelated: value', provider.send(:format_context_item, 'unrelated' => 'value')
  end

  def test_base_covers_context_configuration_fallback_branches
    empty_defaults = Class.new(Prescient::Base) do
      def default_context_configs
        {}
      end
    end.new

    assert_nil empty_defaults.send(:resolve_context_config, {}, nil)
    assert_equal 'default', @base.send(:detect_context_type, 'not a hash')
    assert_nil @base.send(:extract_configured_fields, {}, embedding_fields: [])
    assert_nil @base.send(:extract_configured_fields, {}, embedding_fields: nil)
    assert_equal ['value'], @base.send(
      :extract_configured_fields, { 'field' => 'value' }, embedding_fields: ['field']
    )
    assert_equal({}, @base.send(:build_format_data, {}, fields: [], format: nil, embedding_fields: []))
    assert_equal 'default', @base.send(
      :match_context_by_fields, { 'title' => 'T' },
      'article' => { fields: [], format: nil, embedding_fields: [] }
    )
    assert_equal 'default', @base.send(
      :match_context_by_fields, { 'title' => 'T' },
      'article' => { fields: nil, format: nil, embedding_fields: [] }
    )
    assert_equal 0, @base.send(:calculate_field_match_score, [], [])
  end

  def test_configuration_available_providers_ignores_provider_errors
    failing = Class.new(Prescient::Base) do
      def health_check
        raise StandardError, 'unavailable'
      end
    end
    config = Prescient::Configuration.new
    config.add_provider(:failing, failing)

    assert_empty config.available_providers
    assert_empty Prescient::Configuration.new.available_providers

    config.add_provider(:missing, Prescient::Provider::Ollama,
                        url: 'http://localhost:11434', embedding_model: 'embed', chat_model: 'chat')

    config.stub(:provider, nil) do
      assert_empty config.available_providers
    end

    raising = Class.new(Prescient::Base) do
      def available?
        raise StandardError, 'unavailable'
      end
    end
    config.add_provider(:raising, raising)

    assert_empty config.available_providers
  end

  def test_client_skips_missing_fallback_provider
    failing = Class.new(Prescient::Base) do
      def generate_embedding(_text, **_options)
        raise Prescient::Error, 'failed'
      end

      def health_check
        { status: 'healthy' }
      end
    end
    Prescient.configure do |config|
      config.add_provider(:primary, failing)
      config.fallback_providers = [:missing]
    end

    assert_raises(Prescient::Error) do
      Prescient.client(:primary).generate_embedding('text')
    end
  end

  def test_ollama_response_error_mapping
    provider = Prescient::Provider::Ollama.new(
      url: 'http://localhost:11434', embedding_model: 'embed', chat_model: 'chat',
    )
    {
      429 => Prescient::RateLimitError,
      401 => Prescient::AuthenticationError,
      500 => Prescient::Error,
      418 => Prescient::Error,
    }.each do |code, error_class|
      response = response_double(code)
      assert_raises(error_class) { provider.send(:validate_response!, response, 'operation') }
    end
  end

  def test_openai_health_check_returns_unhealthy_for_http_failure
    provider = Prescient::Provider::OpenAI.new(
      api_key: 'key', embedding_model: 'embed', chat_model: 'chat',
    )
    response = response_double(500)
    provider.class.stubs(:get).returns(response)

    result = provider.health_check

    assert_equal 'unhealthy', result[:status]
  end

  def test_openai_response_error_mapping
    provider = Prescient::Provider::OpenAI.new(
      api_key: 'key', embedding_model: 'embed', chat_model: 'chat',
    )

    {
      400 => Prescient::Error,
      403 => Prescient::AuthenticationError,
      429 => Prescient::RateLimitError,
      500 => Prescient::Error,
      418 => Prescient::Error,
    }.each do |code, error_class|
      assert_raises(error_class) { provider.send(:validate_response!, response_double(code), 'operation') }
    end
  end

  def test_anthropic_response_error_mapping
    provider = Prescient::Provider::Anthropic.new(api_key: 'key', model: 'model')

    {
      400 => Prescient::Error,
      403 => Prescient::AuthenticationError,
      429 => Prescient::RateLimitError,
      500 => Prescient::Error,
      418 => Prescient::Error,
    }.each do |code, error_class|
      assert_raises(error_class) { provider.send(:validate_response!, response_double(code), 'operation') }
    end
  end

  def test_huggingface_response_error_mapping
    provider = Prescient::Provider::HuggingFace.new(
      api_key: 'key', embedding_model: 'embed', chat_model: 'chat',
    )

    {
      400 => Prescient::Error,
      403 => Prescient::AuthenticationError,
      429 => Prescient::RateLimitError,
      500 => Prescient::Error,
      418 => Prescient::Error,
    }.each do |code, error_class|
      assert_raises(error_class) { provider.send(:validate_response!, response_double(code), 'operation') }
    end
  end

  def test_huggingface_loading_and_malformed_503_responses
    provider = Prescient::Provider::HuggingFace.new(
      api_key: 'key', embedding_model: 'embed', chat_model: 'chat',
    )
    loading = response_double(503, parsed_response: { 'error' => 'Model is loading' })
    not_loading = response_double(503, parsed_response: { 'error' => 'Other failure' })
    empty_body = response_double(503, parsed_response: {})
    malformed = response_double(503, parsed_response_error: StandardError.new('invalid'))

    assert_raises(Prescient::Error) do
      provider.send(:validate_response!, loading, 'operation')
    end
    assert_raises(Prescient::Error) do
      provider.send(:validate_response!, not_loading, 'operation')
    end
    assert_raises(Prescient::Error) do
      provider.send(:validate_response!, empty_body, 'operation')
    end
    assert_raises(Prescient::Error) { provider.send(:validate_response!, malformed, 'operation') }
  end

  private

  def response_double(code, parsed_response: {}, parsed_response_error: nil)
    response = mock("response-#{code}")
    response.stubs(:success?).returns(false)
    response.stubs(:code).returns(code)
    response.stubs(:message).returns('failure')
    response.stubs(:body).returns('failure body')
    if parsed_response_error
      response.stubs(:parsed_response).raises(parsed_response_error)
    else
      response.stubs(:parsed_response).returns(parsed_response)
    end
    response
  end
end
