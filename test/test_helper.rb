# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/test/'
end

require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/pride'
require 'mocha/minitest'
require 'prescient'
require 'webmock/minitest'
require 'vcr'

# Configure WebMock
WebMock.disable_net_connect!(allow_localhost: true)

# Configure VCR
VCR.configure do |config|
  config.cassette_library_dir = 'test/fixtures/vcr_cassettes'
  config.hook_into :webmock
  config.default_cassette_options = { record: :once }

  # Filter sensitive data
  config.filter_sensitive_data('<ANTHROPIC_API_KEY>') do
    ENV.fetch('ANTHROPIC_API_KEY', nil)
  end
  config.filter_sensitive_data('<OPENAI_API_KEY>') do
    ENV.fetch('OPENAI_API_KEY', nil)
  end
  config.filter_sensitive_data('<HUGGINGFACE_API_KEY>') { ENV.fetch('HUGGINGFACE_API_KEY', nil) }
end

# Base test class
class PrescientTest < Minitest::Test
  def setup
    Prescient.reset_configuration!
  end
end
