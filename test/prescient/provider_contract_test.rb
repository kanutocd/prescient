# frozen_string_literal: true

require 'test_helper'

class ProviderContractTest < PrescientTest
  PROVIDER_CLASSES = {
    ollama:      Prescient::Provider::Ollama,
    anthropic:   Prescient::Provider::Anthropic,
    openai:      Prescient::Provider::OpenAI,
    huggingface: Prescient::Provider::HuggingFace,
    gemini:      Prescient::Provider::Gemini,
    mistral:     Prescient::Provider::Mistral,
  }.freeze

  PROVIDER_CONFIGS = {
    ollama:      {
      url:             'http://localhost:11434',
      embedding_model: 'nomic-embed-text',
      chat_model:      'llama3.2:3b',
    },
    anthropic:   {
      api_key: 'test-api-key',
      model:   'claude-3-haiku-20240307',
    },
    openai:      {
      api_key:         'test-api-key',
      embedding_model: 'text-embedding-3-small',
      chat_model:      'gpt-4.1-mini',
    },
    huggingface: {
      api_key:         'test-api-key',
      embedding_model: 'sentence-transformers/all-MiniLM-L6-v2',
      chat_model:      'google/gemma-2-2b-it',
    },
    gemini:      {
      api_key:         'test-api-key',
      embedding_model: 'gemini-embedding-001',
      chat_model:      'gemini-2.5-flash',
    },
    mistral:     {
      api_key:         'test-api-key',
      embedding_model: 'mistral-embed',
      chat_model:      'mistral-large-latest',
    },
  }.freeze
  HEALTH_STATUSES = ['healthy', 'partial', 'unhealthy', 'unavailable'].freeze
  BOOLEAN_VALUES = [true, false].freeze

  def test_all_providers_expose_the_common_contract
    PROVIDER_CONFIGS.each do |name, options|
      provider = PROVIDER_CLASSES.fetch(name).new(**options)

      assert_respond_to provider, :generate_embedding
      assert_respond_to provider, :generate_response
      assert_respond_to provider, :health_check
      assert_respond_to provider, :available?
    end
  end

  def test_available_uses_reachability_for_every_provider
    PROVIDER_CONFIGS.each do |name, options|
      provider = PROVIDER_CLASSES.fetch(name).new(**options)
      provider.stubs(:health_check).returns(
        { status: 'unhealthy', provider: name.to_s, reachable: true, ready: false },
      )

      assert_predicate provider, :available?, "#{name} should be available when reachable"
    end
  end

  def test_unreachable_provider_is_not_available_even_with_healthy_status
    PROVIDER_CONFIGS.each do |name, options|
      provider = PROVIDER_CLASSES.fetch(name).new(**options)
      provider.stubs(:health_check).returns(
        { status: 'healthy', provider: name.to_s, reachable: false, ready: false },
      )

      refute_predicate provider, :available?, "#{name} should be unavailable when unreachable"
    end
  end

  def test_health_results_expose_common_status_fields
    PROVIDER_CONFIGS.each do |name, options|
      provider = PROVIDER_CLASSES.fetch(name).new(**options)
      health = {
        status:    'healthy',
        provider:  name.to_s,
        reachable: true,
        ready:     true,
      }
      provider.stubs(:health_check).returns(health)

      result = provider.health_check

      assert_equal name.to_s, result[:provider]
      assert_includes HEALTH_STATUSES, result[:status]
      assert_includes BOOLEAN_VALUES, result[:reachable]
      assert_includes BOOLEAN_VALUES, result[:ready]
    end
  end
end
