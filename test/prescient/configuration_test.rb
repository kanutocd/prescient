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
    assert_empty(@config.providers)
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
end
