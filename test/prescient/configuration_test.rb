# frozen_string_literal: true

require 'test_helper'

class ConfigurationTest < PrescientTest
  def setup
    super
    @config = Prescient::Configuration.new
  end

  def test_initialize_sets_default_values
    assert_equal :ollama, @config.default_provider
    assert_equal 30, @config.timeout
    assert_equal 3, @config.retry_attempts
    assert_in_delta(1.0, @config.retry_delay)
    assert_empty(@config.sensitive_keys)
    assert_empty(@config.providers)
  end

  def test_sensitive_keys_normalizes_custom_keys
    @config.sensitive_keys = ['credit_card', :private_key, :credit_card]

    assert_equal [:credit_card, :private_key], @config.sensitive_keys
  end

  def test_add_provider_adds_provider_configuration
    @config.add_provider(:test, Prescient::Provider::Ollama, url: 'http://test')

    expected = {
      class:   Prescient::Provider::Ollama,
      options: { url: 'http://test' },
    }

    assert_equal expected, @config.providers[:test]
  end

  def test_add_provider_converts_provider_name_to_symbol
    @config.add_provider('test', Prescient::Provider::Ollama, url: 'http://test')

    assert @config.providers.key?(:test)
  end

  def test_provider_returns_provider_instance_with_options
    @config.add_provider(:test, Prescient::Provider::Ollama,
                         url:             'http://localhost:11434',
                         embedding_model: 'test-embed',
                         chat_model:      'test-chat')

    provider = @config.provider(:test)

    assert_instance_of Prescient::Provider::Ollama, provider
    assert_equal 'http://localhost:11434', provider.options[:url]
  end

  def test_provider_returns_nil_for_non_existent_provider
    assert_nil @config.provider(:nonexistent)
  end

  def test_provider_converts_provider_name_to_symbol
    @config.add_provider(:test, Prescient::Provider::Ollama,
                         url:             'http://localhost:11434',
                         embedding_model: 'test-embed',
                         chat_model:      'test-chat')

    provider = @config.provider('test')

    assert_instance_of Prescient::Provider::Ollama, provider
  end

  def test_provider_reuses_registered_provider_instance
    @config.add_provider(:test, Prescient::Provider::Ollama,
                         url:             'http://localhost:11434',
                         embedding_model: 'test-embed',
                         chat_model:      'test-chat')

    assert_same @config.provider(:test), @config.provider(:test)
  end

  def test_reregistering_provider_replaces_cached_instance
    @config.add_provider(:test, Prescient::Provider::Ollama,
                         url:             'http://localhost:11434',
                         embedding_model: 'old-embed',
                         chat_model:      'old-chat')
    old_provider = @config.provider(:test)

    @config.add_provider(:test, Prescient::Provider::Ollama,
                         url:             'http://localhost:11434',
                         embedding_model: 'new-embed',
                         chat_model:      'new-chat')
    new_provider = @config.provider(:test)

    refute_same old_provider, new_provider
    assert_equal 'new-embed', new_provider.options[:embedding_model]
  end

  def test_default_configuration_registers_openai_when_api_key_is_present
    output = run_ruby(
      <<~RUBY,
        ENV["OPENAI_API_KEY"] = "test-openai-key"
        require "prescient"

        provider = Prescient.configuration.providers[:openai]

        abort "OpenAI provider was not registered" unless provider
        abort "Unexpected API key" unless provider[:options]&.fetch(:api_key, "") == "test-openai-key"
      RUBY
      unset: [
        'OPENAI_API_KEY',
        'ANTHROPIC_API_KEY',
        'HUGGINGFACE_API_KEY',
        'GEMINI_API_KEY',
        'MISTRAL_API_KEY',
        'DEEPSEEK_API_KEY',
      ],
    )

    assert_empty output
  end

  def test_default_configuration_registers_huggingface_when_api_key_is_present
    output = run_ruby(
      <<~RUBY,
        ENV["HUGGINGFACE_API_KEY"] = "test-huggingface-key"
        require "prescient"


        provider = Prescient.configuration.providers[:huggingface]

        abort "Hugging Face provider was not registered" unless provider
        abort "Unexpected API key" unless provider[:options]&.fetch(:api_key, "") == "test-huggingface-key"
      RUBY
      unset: [
        'OPENAI_API_KEY',
        'ANTHROPIC_API_KEY',
        'HUGGINGFACE_API_KEY',
        'GEMINI_API_KEY',
        'MISTRAL_API_KEY',
        'DEEPSEEK_API_KEY',
      ],
    )

    assert_empty output
  end

  def test_default_configuration_handles_provider_api_key_combinations
    [{}, { 'OPENAI_API_KEY' => 'openai-key' }, { 'ANTHROPIC_API_KEY' => 'anthropic-key' },
     { 'HUGGINGFACE_API_KEY' => 'huggingface-key' }, { 'GEMINI_API_KEY' => 'gemini-key' },
     { 'MISTRAL_API_KEY' => 'mistral-key' }, { 'DEEPSEEK_API_KEY' => 'deepseek-key' }].each do |env|
      config = Prescient::Configuration.new

      Prescient.send(:configure_default_providers, config, env)

      assert_equal [:ollama, *env.keys.map { |name| name.delete_suffix('_API_KEY').downcase.to_sym }].sort,
                   config.providers.keys.sort
    end
  end
end
