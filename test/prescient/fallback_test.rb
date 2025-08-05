# frozen_string_literal: true

require 'test_helper'

class FallbackTest < PrescientTest
  def setup
    super
    Prescient.configure do |config|
      config.add_provider(:primary, TestProvider, test_option: 'primary')
      config.add_provider(:backup_one, TestProvider, test_option: 'backup_one')
      config.add_provider(:backup_two, TestProvider, test_option: 'backup_two')
      config.fallback_providers = [:backup_one, :backup_two]
    end
  end

  def teardown
    Prescient.reset_configuration!
    super
  end

  def test_fallback_configuration_setup
    config = Prescient.configuration

    assert_equal [:backup_one, :backup_two], config.fallback_providers
    assert_includes config.providers.keys, :primary
    assert_includes config.providers.keys, :backup_one
    assert_includes config.providers.keys, :backup_two
  end

  def test_client_initialization_with_fallback_enabled
    client = Prescient::Client.new(:primary, enable_fallback: true)

    assert_equal :primary, client.provider_name
    assert client.instance_variable_get(:@enable_fallback)
  end

  def test_client_initialization_with_fallback_disabled
    client = Prescient::Client.new(:primary, enable_fallback: false)

    assert_equal :primary, client.provider_name
    refute client.instance_variable_get(:@enable_fallback)
  end

  def test_generate_embedding_falls_back_on_provider_failure
    client = Prescient::Client.new(:primary, enable_fallback: true)

    # Mock primary provider to fail
    client.provider.stubs(:available?).returns(true)
    client.provider.stubs(:generate_embedding).raises(Prescient::Error.new('Primary failed'))

    # Mock backup provider to succeed
    backup_provider = TestProvider.new(test_option: 'backup_one')
    backup_provider.stubs(:available?).returns(true)
    backup_provider.stubs(:generate_embedding).with('test text').returns([0.4, 0.5, 0.6])

    Prescient.configuration.stubs(:provider).with(:backup_one).returns(backup_provider)
    Prescient.configuration.stubs(:provider).with(:backup_two).returns(nil)

    result = client.generate_embedding('test text')

    assert_equal [0.4, 0.5, 0.6], result
  end

  def test_generate_response_falls_back_on_provider_failure
    client = Prescient::Client.new(:primary, enable_fallback: true)

    # Mock primary provider to fail
    client.provider.stubs(:available?).returns(true)
    client.provider.stubs(:generate_response).raises(Prescient::ConnectionError.new('Primary failed'))

    # Mock backup provider to succeed
    backup_provider = TestProvider.new(test_option: 'backup_one')
    backup_provider.stubs(:available?).returns(true)
    backup_provider.stubs(:generate_response).returns({
      response: 'Backup response',
      model:    'backup-model',
      provider: 'backup_one',
    })

    Prescient.configuration.stubs(:provider).with(:backup_one).returns(backup_provider)

    result = client.generate_response('test prompt')

    assert_equal 'Backup response', result[:response]
    assert_equal 'backup-model', result[:model]
  end

  def test_fallback_skips_unavailable_providers
    client = Prescient::Client.new(:primary, enable_fallback: true)

    # Mock primary provider to fail
    client.provider.stubs(:available?).returns(true)
    client.provider.stubs(:generate_embedding).raises(Prescient::Error.new('Primary failed'))

    # Mock first backup as unavailable
    backup1_provider = TestProvider.new(test_option: 'backup_one')
    backup1_provider.stubs(:available?).returns(false)

    # Mock second backup as available and working
    backup2_provider = TestProvider.new(test_option: 'backup_two')
    backup2_provider.stubs(:available?).returns(true)
    backup2_provider.stubs(:generate_embedding).with('test text').returns([0.7, 0.8, 0.9])

    Prescient.configuration.stubs(:provider).with(:backup_one).returns(backup1_provider)
    Prescient.configuration.stubs(:provider).with(:backup_two).returns(backup2_provider)

    result = client.generate_embedding('test text')

    assert_equal [0.7, 0.8, 0.9], result
  end

  def test_fallback_raises_error_when_all_providers_fail
    client = Prescient::Client.new(:primary, enable_fallback: true)

    # Mock all providers to fail
    client.provider.stubs(:available?).returns(true)
    client.provider.stubs(:generate_embedding).raises(Prescient::Error.new('Primary failed'))

    backup1_provider = TestProvider.new(test_option: 'backup_one')
    backup1_provider.stubs(:available?).returns(true)
    backup1_provider.stubs(:generate_embedding).raises(Prescient::Error.new('Backup1 failed'))

    backup2_provider = TestProvider.new(test_option: 'backup_two')
    backup2_provider.stubs(:available?).returns(true)
    backup2_provider.stubs(:generate_embedding).raises(Prescient::Error.new('Backup2 failed'))

    Prescient.configuration.stubs(:provider).with(:backup_one).returns(backup1_provider)
    Prescient.configuration.stubs(:provider).with(:backup_two).returns(backup2_provider)

    assert_raises(Prescient::Error) do
      client.generate_embedding('test text')
    end
  end

  def test_fallback_disabled_does_not_try_other_providers
    client = Prescient::Client.new(:primary, enable_fallback: false)

    # Mock primary provider to fail
    client.provider.stubs(:generate_embedding).raises(Prescient::Error.new('Primary failed'))

    # Should not try to create backup providers when fallback is disabled
    Prescient.configuration.expects(:provider).with(:backup_one).never
    Prescient.configuration.expects(:provider).with(:backup_two).never

    assert_raises(Prescient::Error) do
      client.generate_embedding('test text')
    end
  end

  def test_available_providers_method
    # Mock provider availability
    primary_provider = TestProvider.new(test_option: 'primary')
    primary_provider.stubs(:available?).returns(true)

    backup1_provider = TestProvider.new(test_option: 'backup_one')
    backup1_provider.stubs(:available?).returns(false)

    backup2_provider = TestProvider.new(test_option: 'backup_two')
    backup2_provider.stubs(:available?).returns(true)

    Prescient.configuration.stubs(:provider).with(:primary).returns(primary_provider)
    Prescient.configuration.stubs(:provider).with(:backup_one).returns(backup1_provider)
    Prescient.configuration.stubs(:provider).with(:backup_two).returns(backup2_provider)

    available = Prescient.configuration.available_providers

    assert_includes available, :primary
    refute_includes available, :backup_one
    assert_includes available, :backup_two
  end

  def test_convenience_methods_support_fallback
    # Test that the class-level convenience methods support fallback
    Prescient.stubs(:client).with(:openai, enable_fallback: true).returns(
      stub(generate_embedding: [0.1, 0.2, 0.3]),
    )

    result = Prescient.generate_embedding('test', provider: :openai, enable_fallback: true)

    assert_equal [0.1, 0.2, 0.3], result
  end

  def test_get_providers_to_try_with_configured_fallbacks
    client = Prescient::Client.new(:primary, enable_fallback: true)
    providers = client.send(:providers_to_try)

    assert_equal [:primary, :backup_one, :backup_two], providers
  end

  def test_providers_to_try_with_no_configured_fallbacks
    # Test with no configured fallback providers
    Prescient.configure do |config|
      config.fallback_providers = []
    end

    client = Prescient::Client.new(:primary, enable_fallback: true)

    # Mock available_providers to return some providers
    Prescient.configuration.stubs(:available_providers).returns([:primary, :backup_one, :backup_two])

    providers = client.send(:providers_to_try)

    assert_equal [:primary, :backup_one, :backup_two], providers
  end

  def test_fallback_preserves_method_arguments
    client = Prescient::Client.new(:primary, enable_fallback: true)

    # Mock primary provider to fail
    client.provider.stubs(:available?).returns(true)
    client.provider.stubs(:generate_response).raises(Prescient::Error.new('Primary failed'))

    # Mock backup provider to succeed and verify arguments
    backup_provider = TestProvider.new(test_option: 'backup_one')
    backup_provider.stubs(:available?).returns(true)
    backup_provider.expects(:generate_response).with(
      'test prompt',
      ['context1', 'context2'],
      temperature: 0.8,
      max_tokens:  100,
    ).returns({ response: 'success' })

    Prescient.configuration.stubs(:provider).with(:backup_one).returns(backup_provider)

    result = client.generate_response(
      'test prompt',
      ['context1', 'context2'],
      temperature: 0.8,
      max_tokens:  100,
    )

    assert_equal 'success', result[:response]
  end

  # Test provider class for fallback testing
  class TestProvider < Prescient::Base
    def generate_embedding(_text, **_options)
      [0.1, 0.2, 0.3]
    end

    def generate_response(_prompt, _context_items = [], **_options)
      {
        response: 'Test response',
        model:    'test-model',
        provider: 'test',
      }
    end

    def health_check
      {
        status:   'healthy',
        provider: 'test',
        ready:    true,
      }
    end

    def available?
      true
    end

    protected

    def validate_configuration!
      # No validation needed for test
    end
  end
end
