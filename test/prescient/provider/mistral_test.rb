# frozen_string_literal: true

require "test_helper"

class MistralProviderTest < PrescientTest
  def setup
    super
    @provider = Prescient::Provider::Mistral.new(
      api_key: "test-api-key",
      embedding_model: "mistral-embed",
      chat_model: "mistral-large-latest",
      timeout: 30
    )
  end

  def test_initialize_sets_configuration
    assert_equal "test-api-key", @provider.options[:api_key]
    assert_equal "mistral-embed", @provider.options[:embedding_model]
    assert_equal "mistral-large-latest", @provider.options[:chat_model]
    assert_equal 30, @provider.options[:timeout]
  end

  def test_initialize_validates_required_options
    assert_raises(Prescient::Error) do
      Prescient::Provider::Mistral.new(embedding_model: "test", chat_model: "chat")
    end

    assert_raises(Prescient::Error) do
      Prescient::Provider::Mistral.new(api_key: "test", chat_model: "chat")
    end

    assert_raises(Prescient::Error) do
      Prescient::Provider::Mistral.new(api_key: "test", embedding_model: "embedding")
    end
  end

  def test_generate_embedding_success
    response = stub(success?: true, parsed_response: { "data" => [{ "embedding" => [0.1, 0.2] }] })
    @provider.class.expects(:post).with(
      "/v1/embeddings",
      has_entries(
        headers: {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer test-api-key"
        },
        body: regexp_matches(/mistral-embed.*test text/)
      )
    ).returns(response)

    assert_equal [0.1, 0.2], @provider.generate_embedding("test text")
  end

  def test_generate_embedding_validates_configured_dimensions_and_missing_data
    provider = Prescient::Provider::Mistral.new(
      api_key: "test-api-key", embedding_model: "embedding", chat_model: "chat", embedding_dimensions: 3
    )
    response = stub(success?: true, parsed_response: { "data" => [{ "embedding" => [0.1, 0.2] }] })
    provider.class.expects(:post).returns(response)

    assert_raises(Prescient::InvalidResponseError) do
      provider.generate_embedding("test")
    end

    missing_response = stub(success?: true, parsed_response: { "data" => [] })
    @provider.class.expects(:post).returns(missing_response)
    assert_raises(Prescient::InvalidResponseError) { @provider.generate_embedding("test") }
  end

  def test_generate_response_success_with_string_content
    response = stub(
      success?: true,
      parsed_response: {
        "choices" => [{
          "message" => { "content" => "Hello from Mistral" },
          "finish_reason" => "stop"
        }],
        "usage" => { "total_tokens" => 12 }
      }
    )
    @provider.class.expects(:post).with(
      "/v1/chat/completions",
      has_entries(
        headers: {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer test-api-key"
        },
        body: regexp_matches(/mistral-large-latest/)
      )
    ).returns(response)

    result = @provider.generate_response("test prompt")

    assert_equal "Hello from Mistral", result[:response]
    assert_equal "mistral-large-latest", result[:model]
    assert_equal "mistral", result[:provider]
    assert_equal "stop", result[:metadata][:finish_reason]
  end

  def test_generate_response_supports_content_chunks_and_options
    response = stub(
      success?: true,
      parsed_response: {
        "choices" => [{
          "message" => { "content" => [{ "type" => "text", "text" => "chunked " }, { "text" => "answer" }] }
        }]
      }
    )
    @provider.class.expects(:post).with(
      "/v1/chat/completions",
      has_entries(body: regexp_matches(/1000.*0\.8.*0\.95/))
    ).returns(response)

    result = @provider.generate_response(
      "test", [{ "title" => "Document", "content" => "Context" }],
      max_tokens: 1000, temperature: 0.8, top_p: 0.95
    )

    assert_equal "chunked answer", result[:response]
  end

  def test_generate_response_ignores_non_hash_content_chunks
    response = stub(
      success?: true,
      parsed_response: {
        "choices" => [{ "message" => { "content" => ["invalid", { "text" => "answer" }] } }]
      }
    )
    @provider.class.expects(:post).returns(response)

    assert_equal "answer", @provider.generate_response("test")[:response]
  end

  def test_generate_response_rejects_missing_content
    response = stub(success?: true, parsed_response: { "choices" => [] })
    @provider.class.expects(:post).returns(response)

    assert_raises(Prescient::InvalidResponseError) { @provider.generate_response("test") }
  end

  def test_health_check_success_and_missing_models
    response = stub(
      success?: true,
      parsed_response: {
        "data" => [
          { "id" => "mistral-embed" },
          { "id" => "mistral-large-latest" }
        ]
      }
    )
    @provider.class.expects(:get).with(
      "/v1/models",
      has_entries(
        headers: {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer test-api-key"
        }
      )
    ).returns(response)

    result = @provider.health_check

    assert_equal "healthy", result[:status]
    assert_equal %w[mistral-embed mistral-large-latest], result[:models_available]
    assert result[:embedding_model][:available]
    assert result[:chat_model][:available]
    assert result[:ready]

    missing_response = stub(success?: true, parsed_response: { "data" => [{ "id" => "other-model" }] })
    @provider.class.expects(:get).returns(missing_response)
    result = @provider.health_check

    refute result[:ready]
  end

  def test_health_check_reports_http_and_connection_failures
    response = stub(success?: false, code: 401, message: "Unauthorized")
    @provider.class.expects(:get).returns(response)

    result = @provider.health_check

    assert_equal "unhealthy", result[:status]
    assert_equal "HTTP 401", result[:error]
    refute result[:ready]

    @provider.class.expects(:get).raises(StandardError.new("Connection failed"))
    result = @provider.health_check

    assert_equal "unavailable", result[:status]
  end

  def test_list_models
    response = stub(
      success?: true,
      parsed_response: {
        "data" => [{
          "id" => "mistral-large-latest",
          "object" => "model",
          "created" => 1_700_000_000,
          "owned_by" => "mistralai",
          "capabilities" => { "completion_chat" => true },
          "max_context_length" => 128_000
        }]
      }
    )
    @provider.class.expects(:get).returns(response)

    result = @provider.list_models

    assert_equal "mistral-large-latest", result.first[:name]
    assert_equal "mistralai", result.first[:owned_by]
    assert_equal 128_000, result.first[:max_context_length]
  end
end
