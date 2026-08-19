# frozen_string_literal: true

require 'test_helper'
require 'tempfile'

class CLITest < PrescientTest
  class CLIProvider < Prescient::Base
    class << self
      attr_accessor :last_options
    end

    def initialize(**options)
      self.class.last_options = options
      super
    end

    def generate_embedding(_text, **options)
      options[:model] ? [options[:model]] : [@options[:embedding_model] || 0.1, 0.2]
    end

    def generate_response(prompt, _context_items = [], **options)
      {
        response: "response to #{prompt}",
        model:    options[:model] || @options[:chat_model],
        provider: 'cli-test',
      }
    end

    def health_check
      {
        status:    @options[:status] || 'healthy',
        provider:  'cli-test',
        reachable: @options.fetch(:reachable, true),
        ready:     true,
      }
    end

    protected

    def validate_configuration!
      # No validation needed for this test provider.
    end
  end

  class CLITool < Prescient::Tool::Base
    def search(query, limit: nil)
      snippet = query == 'no snippet' ? '' : 'Snippet'
      results = [{ title: 'Result', url: 'https://example.test', snippet: snippet }]
      { tool: 'web_search', query: query, source: 'test', results: results.first(limit || 1) }
    end
  end

  def setup
    super
    @prescient_config = ENV.delete('PRESCIENT_CONFIG')
    Prescient.configure do |config|
      config.default_provider = :test
      config.add_provider(:test, CLIProvider, chat_model: 'configured-model')
      config.add_provider(:offline, CLIProvider, reachable: false, status: 'unavailable')
      config.add_tool(:web_search, CLITool)
    end
  end

  def teardown
    ENV['PRESCIENT_CONFIG'] = @prescient_config if @prescient_config
    super
  end

  # rubocop:disable Minitest/MultipleAssertions
  def test_help_and_unknown_command_return_usage_status
    status, output, errors = run_cli([])

    assert_equal 2, status

    assert_includes output, 'Usage: prescient COMMAND'

    assert_includes output, '--config PATH'

    assert_includes output, '--api-key-env NAME'

    assert_includes output, '--embedding-model NAME'

    assert_includes output, '--system-prompt TEXT'

    assert_includes output, '--prompt-templates-file PATH'

    assert_includes output, 'Global options:'

    assert_includes output, 'Search options:'

    assert_empty errors

    status, _output, errors = run_cli(['unknown'])

    assert_equal 2, status

    assert_includes errors, 'unknown command'

    status, output, _errors = run_cli(['help'])

    assert_equal 0, status

    assert_includes output, 'generate TEXT'

    assert_includes output, '--chat-model NAME'

    status, output, _errors = run_cli(['providers', '--help'])

    assert_equal 0, status

    assert_includes output, 'List configured providers'

    status, output, _errors = run_cli(['search', '--help'])

    assert_equal 0, status
    assert_includes output, 'Global options:'
    assert_includes output, 'Search options:'
  end
  # rubocop:enable Minitest/MultipleAssertions

  def test_each_command_supports_help
    ['health', 'generate', 'embed', 'search'].each do |command|
      status, output, _errors = run_cli([command, '--help'])

      assert_equal 0, status

      assert_includes output, 'Usage:'
    end

    status, output, _errors = run_cli(['config', 'validate', '--help'])

    assert_equal 0, status

    assert_includes output, 'Validate the current configuration'
  end

  def test_search_options_are_added_only_when_requested
    cli = Prescient::CLI.new([], input: StringIO.new, output: StringIO.new, errors: StringIO.new)
    parser = OptionParser.new

    cli.send(:add_tool_options, parser, {}, tool: false, limit: true, generate: false)
    cli.send(:add_tool_options, parser, {}, tool: true, limit: false, generate: false)
  end

  def test_providers_support_text_and_json_output
    status, output, _errors = run_cli(['providers'])

    assert_equal 0, status

    assert_includes output, "test\t#{CLIProvider.name}"

    status, output, _errors = run_cli(['providers', '--format', 'json'])

    assert_equal 0, status

    provider_names = JSON.parse(output)['providers'].map { |provider| provider['name'] }

    assert_equal ['test', 'offline'], provider_names
  end

  def test_health_supports_provider_filter_and_json_output
    status, output, _errors = run_cli(['health', '--provider', 'test'])

    assert_equal 0, status

    assert_includes output, 'test         healthy'

    status, output, _errors = run_cli(['health', '--provider', 'offline', '--format', 'json'])

    assert_equal 1, status

    assert_equal 'unavailable', JSON.parse(output)['offline']['status']
  end

  def test_generate_supports_stdin_text_json_and_model_override
    status, output, _errors = run_cli(['generate', '--model', 'override', 'hello'])

    assert_equal 0, status

    assert_equal "response to hello\n", output

    status, output, _errors = run_cli(['generate', '--format', 'json'], input: StringIO.new('from stdin'))

    assert_equal 0, status

    assert_equal 'from stdin', JSON.parse(output)['response'].sub('response to ', '')
  end

  def test_generate_loads_json_documents_as_context
    path = write_configuration('[{"title":"Ruby"}]')

    status, output, _errors = run_cli(['generate', '--json-file', path, 'Summarize'])

    assert_equal 0, status
    assert_equal "response to Summarize\n", output
  end

  def test_generate_supports_chat_model_and_api_key_overrides_without_mutating_configuration
    status, output, _errors = run_cli(
      ['generate', '--chat-model', 'automation-chat', '--api-key', 'temporary-key', 'hello'],
    )

    assert_equal 0, status

    assert_equal "response to hello\n", output

    assert_equal 'automation-chat', CLIProvider.last_options[:chat_model]

    assert_equal 'temporary-key', CLIProvider.last_options[:api_key]

    assert_equal 'configured-model', Prescient.configuration.provider(:test).options[:chat_model]
  end

  def test_generate_supports_prompt_template_overrides
    template_path = write_configuration(<<~YAML)
      system_prompt: Be concise.
      no_context_template: "%<system_prompt>s\\nUser: %<query>s"
    YAML

    status, output, _errors = run_cli(
      [
        'generate',
        '--prompt-templates-file', template_path,
        '--system-prompt', 'Be precise.',
        'hello'
      ],
    )

    assert_equal 0, status
    assert_equal "response to hello\n", output
    assert_equal 'Be precise.', CLIProvider.last_options.dig(:prompt_templates, :system_prompt)
    assert_equal "%<system_prompt>s\nUser: %<query>s",
                 CLIProvider.last_options.dig(:prompt_templates, :no_context_template)
  end

  def test_embed_supports_embedding_model_and_api_key_environment_overrides
    ENV['PRESCIENT_CLI_TEST_KEY'] = 'environment-key'
    status, output, _errors = run_cli(
      ['embed', '--embedding-model', 'automation-embedding', '--api-key-env', 'PRESCIENT_CLI_TEST_KEY', 'text'],
    )

    assert_equal 0, status

    assert_equal "[\"automation-embedding\",0.2]\n", output

    assert_equal 'automation-embedding', CLIProvider.last_options[:embedding_model]

    assert_equal 'environment-key', CLIProvider.last_options[:api_key]
  ensure
    ENV.delete('PRESCIENT_CLI_TEST_KEY')
  end

  def test_embed_supports_stdin_and_json_output
    status, output, _errors = run_cli(['embed', '--format', 'json'], input: StringIO.new('text'))

    assert_equal 0, status
    result = JSON.parse(output)

    assert_equal [0.1, 0.2], result['embedding']

    assert_equal 2, result['dimensions']

    assert_equal 'test', result['provider']

    status, output, _errors = run_cli(['embed', '--model', 'override', 'text'])

    assert_equal 0, status

    assert_equal "[\"override\"]\n", output
  end

  def test_config_validate_supports_text_and_json_output
    status, output, _errors = run_cli(['config', 'validate'])

    assert_equal 0, status

    assert_equal "configuration valid\n", output

    status, output, _errors = run_cli(['config', 'validate', '--format', 'json'])

    assert_equal 0, status

    assert JSON.parse(output)['valid']
  end

  def test_config_example_outputs_annotated_schema_backed_yaml
    status, output, errors = run_cli(['config', 'example'])

    assert_equal 0, status
    assert_empty errors
    assert_includes output, '# yaml-language-server: $schema=https://raw.githubusercontent.com/kanutocd/prescient/refs/heads/main/schema/prescient.configuration.schema.json'
    assert_includes output, 'version: 1'
    assert_includes output, 'api_key_env: OPENAI_API_KEY'

    assert_includes output, 'prompt_templates:'

    assert_includes output, 'no_context_template:'
    assert_includes output, 'type: deepseek'
    assert_includes output, 'prescient config validate'
  end

  def test_search_supports_json_text_and_limit
    status, output, _errors = run_cli(['search', '--format', 'json', '--limit', '1', 'Ruby tools'])

    assert_equal 0, status

    result = JSON.parse(output)

    assert_equal 'Ruby tools', result['query']
    assert_equal 'test', result['source']

    status, output, _errors = run_cli(['search', 'Ruby tools'])

    assert_equal 0, status
    assert_includes output, 'https://example.test'
    assert_includes output, 'Snippet'

    status, output, _errors = run_cli(['search', 'no snippet'])

    assert_equal 0, status
    refute_includes output, 'Snippet'
  end

  def test_search_can_explicitly_generate_with_results_as_context
    status, output, _errors = run_cli(
      ['search', '--generate', '--provider', 'test', '--format', 'json', 'Ruby tools'],
    )

    assert_equal 0, status
    assert_equal 'response to Ruby tools', JSON.parse(output)['response']

    status, output, _errors = run_cli(['search', '--generate', 'Ruby tools'])

    assert_equal 0, status
    assert_equal "response to Ruby tools\n", output
  end

  def test_search_rejects_missing_tool
    Prescient.configuration.tools.clear

    status, _output, errors = run_cli(['search', 'Ruby tools'])

    assert_equal 2, status
    assert_includes errors, 'tool not configured'
  end

  def test_configuration_example_help_and_invalid_prompt_template_file
    status, output, _errors = run_cli(['config', 'example', '--help'])

    assert_equal 0, status
    assert_includes output, 'Generate an annotated YAML configuration example'

    path = write_configuration('- invalid\n')
    status, _output, errors = run_cli(['generate', '--prompt-templates-file', path, 'hello'])

    assert_equal 2, status
    assert_includes errors, 'must contain a mapping'
  end

  def test_cli_loads_configuration_from_yaml_file
    config_path = write_configuration(<<~YAML)
      version: 1
      default_provider: test
      providers:
        test:
          type: ollama
          url: http://localhost:11434
          chat_model: configured-model
          embedding_model: configured-embedding
    YAML

    status, output, _errors = run_cli(['--config', config_path, 'config', 'validate'])

    assert_equal 0, status
    assert_equal "configuration valid\n", output

    status, output, _errors = run_cli(['--config', config_path, 'providers', '--format', 'json'])

    assert_equal 0, status
    assert_includes JSON.parse(output)['providers'].map { |provider| provider['name'] }, 'test'
  end

  def test_usage_errors_are_reported_without_a_stack_trace
    status, _output, errors = run_cli(['generate'], input: TTYInput.new)

    assert_equal 2, status

    assert_includes errors, 'missing prompt'

    status, _output, errors = run_cli(['config', 'unknown'])

    assert_equal 2, status

    assert_includes errors, 'unknown config command'

    status, _output, errors = run_cli(['providers', '--invalid'])

    assert_equal 2, status

    assert_includes errors, 'invalid option'

    Prescient.reset_configuration!
    status, _output, errors = run_cli(['health'])

    assert_equal 2, status

    assert_includes errors, 'no providers are configured'

    Prescient.configure do |config|
      config.default_provider = :missing
    end
    status, _output, errors = run_cli(['config', 'validate'])

    assert_equal 1, status

    assert_includes errors, 'default provider is not configured'
  end

  def test_provider_errors_return_operational_failure_status
    Prescient.configuration.add_provider(:broken, BrokenCLIProvider)

    status, _output, errors = run_cli(['generate', '--provider', 'broken', 'hello'])

    assert_equal 1, status

    assert_equal "prescient: broken\n", errors
  end

  def test_override_validation_rejects_conflicting_options_and_missing_environment_keys
    status, _output, errors = run_cli(['generate', '--model', 'one', '--chat-model', 'two', 'hello'])

    assert_equal 2, status

    assert_includes errors, 'cannot be combined'

    status, _output, errors = run_cli(
      ['generate', '--api-key', 'one', '--api-key-env', 'MISSING_CLI_KEY', 'hello'],
    )

    assert_equal 2, status

    assert_includes errors, 'cannot be combined'

    status, _output, errors = run_cli(['embed', '--api-key-env', 'MISSING_CLI_KEY', 'hello'])

    assert_equal 2, status

    assert_includes errors, 'environment variable not set'
  end

  private

  def run_cli(arguments, input: StringIO.new)
    output = StringIO.new
    errors = StringIO.new
    status = Prescient::CLI.run(arguments, input:, output:, errors:)
    [status, output.string, errors.string]
  end

  def write_configuration(content)
    file = Tempfile.new(['prescient-cli', '.yml'])
    file.write(content)
    file.flush
    file.close
    file.path
  end

  class BrokenCLIProvider < CLIProvider
    def generate_response(*_args, **_options)
      raise Prescient::Error, 'broken'
    end
  end

  class TTYInput < StringIO
    def tty?
      true
    end
  end
end
