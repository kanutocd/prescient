# frozen_string_literal: true

require "test_helper"

class GeminiProviderTest < PrescientTest
  def setup
    super
    @provider = Prescient::Provider::Gemini.new(
      api_key: "test-api-key",
      embedding_model: "gemini-embedding-001",
      chat_model: "gemini-2.5-flash",
      timeout: 30
    )
  end

  def test_initialize_sets_configuration
    assert_equal "test-api-key", @provider.options[:api_key]
    assert_equal "gemini-embedding-001", @provider.options[:embedding_model]
    assert_equal "gemini-2.5-flash", @provider.options[:chat_model]
    assert_equal 30, @provider.options[:timeout]
  end

  def test_initialize_validates_required_options
    assert_raises(Prescient::Error) do
      Prescient::Provider::Gemini.new(embedding_model: "test", chat_model: "chat")
    end

    assert_raises(Prescient::Error) do
      Prescient::Provider::Gemini.new(api_key: "test", chat_model: "chat")
    end

    assert_raises(Prescient::Error) do
      Prescient::Provider::Gemini.new(api_key: "test", embedding_model: "embedding")
    end
  end

  def test_generate_embedding_success
    response = stub(success?: true, parsed_response: { "embedding" => { "values" => [0.1, 0.2] } })

    @provider.class.expects(:post).with(
      "/v1beta/models/gemini-embedding-001:embedContent",
      has_entries(
        headers: {
          "Content-Type" => "application/json",
          "x-goog-api-key" => "test-api-key"
        },
        body: regexp_matches(/test text/)
      )
    ).returns(response)

    assert_equal [0.1, 0.2], @provider.generate_embedding("test text")
  end

  def test_generate_embedding_validates_configured_dimensions
    provider = Prescient::Provider::Gemini.new(
      api_key: "test-api-key", embedding_model: "embedding", chat_model: "chat", embedding_dimensions: 3
    )
    response = stub(success?: true, parsed_response: { "embedding" => { "values" => [0.1, 0.2] } })
    provider.class.expects(:post).returns(response)

    assert_raises(Prescient::InvalidResponseError) { provider.generate_embedding("test") }
  end

  def test_generate_embedding_rejects_missing_embedding
    response = stub(success?: true, parsed_response: { "embedding" => {} })
    @provider.class.expects(:post).returns(response)

    assert_raises(Prescient::InvalidResponseError) { @provider.generate_embedding("test") }
  end

  def test_generate_response_success
    response = stub(
      success?: true,
      parsed_response: {
        "candidates" => [{
          "content" => { "parts" => [{ "text" => "Hello " }, { "text" => "from Gemini" }] },
          "finishReason" => "STOP"
        }],
        "usageMetadata" => { "totalTokenCount" => 12 }
      }
    )
    @provider.class.expects(:post).with(
      "/v1beta/models/gemini-2.5-flash:generateContent",
      has_entries(
        headers: {
          "Content-Type" => "application/json",
          "x-goog-api-key" => "test-api-key"
        },
        body: regexp_matches(/maxOutputTokens.*2000/)
      )
    ).returns(response)

    result = @provider.generate_response("test prompt")

    assert_equal "Hello from Gemini", result[:response]
    assert_equal "gemini-2.5-flash", result[:model]
    assert_equal "gemini", result[:provider]
    assert_equal "STOP", result[:metadata][:finish_reason]
    assert_equal 12, result[:metadata][:usage]["totalTokenCount"]
  end

  def test_generate_response_supports_context_and_options
    response = stub(
      success?: true,
      parsed_response: { "candidates" => [{ "content" => { "parts" => [{ "text" => "answer" }] } }] }
    )
    @provider.class.expects(:post).with(
      "/v1beta/models/gemini-2.5-flash:generateContent",
      has_entries(body: regexp_matches(/1000.*0\.8.*0\.95/))
    ).returns(response)

    result = @provider.generate_response(
      "test", [{ "title" => "Document", "content" => "Context" }],
      max_tokens: 1000, temperature: 0.8, top_p: 0.95
    )

    assert_equal "answer", result[:response]
  end

  def test_generate_response_rejects_missing_content
    response = stub(success?: true, parsed_response: { "candidates" => [] })
    @provider.class.expects(:post).returns(response)

    assert_raises(Prescient::InvalidResponseError) { @provider.generate_response("test") }
  end

  def test_health_check_success_and_missing_models
    response = stub(
      success?: true,
      parsed_response: {
        "models" => [
          { "name" => "models/gemini-embedding-001", "supportedGenerationMethods" => ["embedContent"] },
          { "name" => "models/gemini-2.5-flash", "supportedGenerationMethods" => ["generateContent"] }
        ]
      }
    )
    @provider.class.expects(:get).with(
      "/v1beta/models",
      has_entries(
        headers: {
          "Content-Type" => "application/json",
          "x-goog-api-key" => "test-api-key"
        }
      )
    ).returns(response)

    result = @provider.health_check

    assert_equal "healthy", result[:status]
    assert_equal "gemini", result[:provider]
    assert_equal ["gemini-embedding-001", "gemini-2.5-flash"], result[:models_available]
    assert result[:embedding_model][:available]
    assert result[:chat_model][:available]
    assert result[:ready]
  end

  def test_health_check_reports_missing_models
    response = stub(
      success?: true,
      parsed_response: { "models" => [{ "name" => "models/gemini-2.5-flash", "supportedGenerationMethods" => [] }] }
    )
    @provider.class.expects(:get).returns(response)

    result = @provider.health_check

    refute result[:embedding_model][:available]
    refute result[:chat_model][:available]
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
    assert_equal "Unexpected error: Connection failed", result[:message]
  end

  def test_list_models
    response = stub(
      success?: true,
      parsed_response: {
        "models" => [{
          "name" => "models/gemini-2.5-flash",
          "displayName" => "Gemini 2.5 Flash",
          "supportedGenerationMethods" => ["generateContent"],
          "inputTokenLimit" => 1_000_000,
          "outputTokenLimit" => 8192
        }]
      }
    )
    @provider.class.expects(:get).returns(response)

    result = @provider.list_models

    assert_equal "gemini-2.5-flash", result.first[:name]
    assert_equal "Gemini 2.5 Flash", result.first[:display_name]
  end
end
