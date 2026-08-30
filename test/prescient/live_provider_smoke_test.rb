# frozen_string_literal: true

require "test_helper"

class LiveProviderSmokeTest < PrescientTest
  def test_ollama_live_embedding
    provider = live_provider(:ollama)

    embedding = provider.generate_embedding("Prescient live smoke test")

    assert_operator embedding.length, :>, 0
  end

  def test_anthropic_live_response
    provider = live_provider(:anthropic)

    response = provider.generate_response("Reply with the word healthy.")

    refute_empty response[:response].to_s
  end

  def test_openai_live_embedding
    provider = live_provider(:openai)

    embedding = provider.generate_embedding("Prescient live smoke test")

    assert_operator embedding.length, :>, 0
  end

  def test_huggingface_live_embedding
    provider = live_provider(:huggingface)

    embedding = provider.generate_embedding("Prescient live smoke test")

    assert_operator embedding.length, :>, 0
  end

  private

  def live_provider(name)
    unless ENV["PRESCIENT_LIVE_SMOKE"] == "1" && live_provider_names.include?(name)
      skip "Set PRESCIENT_LIVE_SMOKE=1 and include #{name} in PRESCIENT_LIVE_PROVIDERS to run"
    end

    provider_class, options = provider_definition(name)
    provider_class.new(**options)
  end

  def live_provider_names
    ENV.fetch("PRESCIENT_LIVE_PROVIDERS", "").split(",").map { |name| name.strip.to_sym }
  end

  def provider_definition(name)
    case name
    when :ollama
      [Prescient::Provider::Ollama, {
        url: ENV.fetch("OLLAMA_URL", "http://localhost:11434"),
        embedding_model: ENV.fetch("OLLAMA_EMBEDDING_MODEL", "nomic-embed-text"),
        chat_model: ENV.fetch("OLLAMA_CHAT_MODEL", "llama3.2:3b")
      }]
    when :anthropic
      [Prescient::Provider::Anthropic, {
        api_key: ENV.fetch("ANTHROPIC_API_KEY"),
        model: ENV.fetch("ANTHROPIC_MODEL", "claude-sonnet-4-20250514")
      }]
    when :openai
      [Prescient::Provider::OpenAI, {
        api_key: ENV.fetch("OPENAI_API_KEY"),
        embedding_model: ENV.fetch("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small"),
        chat_model: ENV.fetch("OPENAI_CHAT_MODEL", "gpt-4.1-mini")
      }]
    when :huggingface
      [Prescient::Provider::HuggingFace, {
        api_key: ENV.fetch("HUGGINGFACE_API_KEY"),
        embedding_model: ENV.fetch("HUGGINGFACE_EMBEDDING_MODEL", "sentence-transformers/all-MiniLM-L6-v2"),
        chat_model: ENV.fetch("HUGGINGFACE_CHAT_MODEL", "google/gemma-2-2b-it")
      }]
    else
      raise ArgumentError, "Unsupported live provider: #{name}"
    end
  end
end
