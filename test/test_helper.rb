# frozen_string_literal: true

unless ENV['COVERAGE'] == 'false'
  require 'simplecov'

  SimpleCov.start do
    enable_coverage :branch
    add_filter '/test/'
    minimum_coverage line: 99, branch: 99
  end
end

require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/pride'
require 'mocha/minitest'
require 'prescient'
require 'webmock/minitest'
require 'vcr'
require 'open3'
require 'rbconfig'

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

  def run_ruby(source, env: {}, unset: [])
    child_env = ENV.to_h
    unset.each do |key|
      child_env.delete(key)
    end
    child_env.merge!(env)

    stdout, stderr, status = Open3.capture3(
      child_env,
      RbConfig.ruby,
      '-Ilib',
      '-e',
      source,
      chdir: File.expand_path('..', __dir__),
    )

    assert_predicate status, :success?, <<~ERROR
      Ruby subprocess failed with exit status #{status.exitstatus}.

      STDOUT:
      #{stdout}

      STDERR:
      #{stderr}
    ERROR

    stdout
  end
end
