# frozen_string_literal: true

require 'test_helper'

class AiProvidersTest < PrescientTest
  def test_configure_yields_configuration_object
    yielded_config = nil
    Prescient.configure do |config|
      yielded_config = config
    end

    assert_equal Prescient.configuration, yielded_config
  end

  def test_configure_allows_setting_default_provider
    Prescient.configure do |config|
      config.default_provider = :openai
    end

    assert_equal :openai, Prescient.configuration.default_provider
  end

  def test_configuration_returns_configuration_instance
    assert_instance_of Prescient::Configuration, Prescient.configuration
  end

  def test_configuration_returns_same_instance_on_multiple_calls
    config_one = Prescient.configuration
    config_two = Prescient.configuration

    assert_equal config_one, config_two
  end

  def test_reset_configuration_creates_new_configuration_instance
    old_config = Prescient.configuration
    Prescient.reset_configuration!
    new_config = Prescient.configuration

    refute_equal new_config, old_config
  end

  def test_client_returns_client_instance
    Prescient.configure do |config|
      config.add_provider(:test, Prescient::Provider::Ollama,
                          url:             'http://localhost:11434',
                          embedding_model: 'test-embed',
                          chat_model:      'test-chat')
    end

    client = Prescient.client(:test)

    assert_instance_of Prescient::Client, client
  end

  def test_client_uses_default_provider_when_no_provider_specified
    Prescient.configure do |config|
      config.add_provider(:test, Prescient::Provider::Ollama,
                          url:             'http://localhost:11434',
                          embedding_model: 'test-embed',
                          chat_model:      'test-chat')
      config.default_provider = :test
    end

    client = Prescient.client

    assert_equal :test, client.provider_name
  end

  def test_generate_embedding_delegates_to_client
    setup_test_provider

    client_double = Minitest::Mock.new
    client_double.expect :generate_embedding, [1, 2, 3], ['test'], temperature: 0.5

    Prescient.stub :client, client_double do
      result = Prescient.generate_embedding('test', temperature: 0.5)

      assert_equal [1, 2, 3], result
    end

    client_double.verify
  end

  def test_generate_response_delegates_to_client
    setup_test_provider

    client_double = Minitest::Mock.new
    client_double.expect :generate_response, { response: 'test response' }, ['prompt', ['context']], temperature: 0.7

    Prescient.stub :client, client_double do
      result = Prescient.generate_response('prompt', ['context'], temperature: 0.7)

      assert_equal({ response: 'test response' }, result)
    end

    client_double.verify
  end

  def test_health_check_delegates_to_client
    setup_test_provider

    client_double = Minitest::Mock.new
    client_double.expect :health_check, { status: 'healthy' }

    Prescient.stub :client, client_double do
      result = Prescient.health_check

      assert_equal({ status: 'healthy' }, result)
    end

    client_double.verify
  end

  private

  def setup_test_provider
    Prescient.configure do |config|
      config.add_provider(:test, Prescient::Provider::Ollama,
                          url:             'http://localhost:11434',
                          embedding_model: 'test-embed',
                          chat_model:      'test-chat')
      config.default_provider = :test
    end
  end
end
