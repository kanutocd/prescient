# frozen_string_literal: true

require 'tempfile'
require 'test_helper'

class ConfigurationLoaderTest < PrescientTest
  def test_class_helpers_load_yaml_hash_and_file
    path = write_configuration(<<~YAML)
      version: 1
      default_provider: ollama
      providers:
        ollama:
          type: ollama
          url: http://localhost:11434
          chat_model: llama3.2:3b
          embedding_model: nomic-embed-text
    YAML

    from_yaml = Prescient::ConfigurationLoader.load_yaml(File.read(path), env: {})
    from_hash = Prescient::ConfigurationLoader.load_hash(
      YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: true),
      env: {},
    )
    from_file = Prescient::ConfigurationLoader.load_file(path, env: {})

    assert_equal :ollama, from_yaml.default_provider
    assert_equal :ollama, from_hash.default_provider
    assert_equal :ollama, from_file.default_provider
  end

  def test_load_configuration_from_yaml_with_environment_references
    path = write_configuration(<<~YAML)
      $schema: https://github.com/kanutocd/prescient/schema/prescient.configuration.schema.json
      version: 1
      default_provider_env: PRESCIENT_DEFAULT_PROVIDER
      timeout_env: PRESCIENT_TIMEOUT
      fallback_providers:
        - ollama
      sensitive_keys:
        - workspace_secret
      providers:
        demo:
          type: openai
          api_key_env: OPENAI_API_KEY
          chat_model_env: OPENAI_CHAT_MODEL
          embedding_model: ${EMBEDDING_MODEL}
    YAML

    configuration = Prescient.load_configuration(
      path,
      env: {
        'PRESCIENT_DEFAULT_PROVIDER' => 'demo',
        'PRESCIENT_TIMEOUT'          => '45',
        'OPENAI_API_KEY'             => 'loader-key',
        'OPENAI_CHAT_MODEL'          => 'gpt-4.1-mini',
        'EMBEDDING_MODEL'            => 'text-embedding-3-small',
      },
    )

    assert_equal :demo, configuration.default_provider
    assert_equal 45, configuration.timeout
    assert_equal [:ollama], configuration.fallback_providers
    assert_equal [:workspace_secret], configuration.sensitive_keys

    provider = configuration.provider(:demo)

    assert_instance_of Prescient::Provider::OpenAI, provider
    assert_equal 'loader-key', provider.options[:api_key]
    assert_equal 'gpt-4.1-mini', provider.options[:chat_model]
    assert_equal 'text-embedding-3-small', provider.options[:embedding_model]
  end

  def test_load_configuration_without_path_uses_environment_defaults
    configuration = Prescient.load_configuration(nil, env: {})

    assert_instance_of Prescient::Configuration, configuration
    assert_includes configuration.providers, :ollama
  end

  def test_load_configuration_supports_prompt_templates
    configuration = Prescient::ConfigurationLoader.load_hash(
      {
        providers: {
          demo: {
            type:             'openai',
            api_key:          'key',
            chat_model:       'chat-model',
            embedding_model:  'embedding-model',
            prompt_templates: {
              system_prompt:         'Be concise.',
              no_context_template:   '%<system_prompt>s\nUser: %<query>s',
              with_context_template: '%<system_prompt>s\nContext: %<context>s\nUser: %<query>s',
            },
          },
        },
      },
      env: {},
    )

    assert_equal 'Be concise.', configuration.provider(:demo).options.dig(:prompt_templates, :system_prompt)
    assert_equal '%<system_prompt>s\nUser: %<query>s',
                 configuration.provider(:demo).options.dig(:prompt_templates, :no_context_template)
  end

  # rubocop:disable Layout/HashAlignment, Style/BlockDelimiters, Minitest/MultipleAssertions, Minitest/AssertInDelta, Minitest/EmptyLineBeforeAssertionMethods
  def test_load_configuration_supports_tools_and_environment_references
    env = {
      'SEARXNG_URL' => 'http://search.local:8080',
      'SEARCH_LIMIT' => '7',
    }
    configuration = Prescient::ConfigurationLoader.load_yaml(<<~YAML, env:)
      version: 1
      tools:
        web_search:
          type: searxng
          url_env: SEARXNG_URL
          max_results_env: SEARCH_LIMIT
          categories:
            - general
            - news
    YAML

    tool = configuration.tool(:web_search)

    assert_instance_of Prescient::Tool::SearXNG, tool
    assert_equal 'http://search.local:8080', tool.options[:url]
    assert_equal 7, tool.options[:max_results]
    assert_equal ['general', 'news'], tool.options[:categories]
  end

  def test_load_configuration_rejects_unknown_tools
    error = assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.load_yaml(<<~YAML, env: {})
        version: 1
        tools:
          search:
            type: imaginary
      YAML
    end

    assert_includes error.message, 'Unknown tool type'
  end

  def test_load_configuration_rejects_invalid_tool_shapes_and_keys
    invalid_shape = assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.load_hash({ tools: { search: 'invalid' } }, env: {})
    end
    assert_includes invalid_shape.message, 'must be a mapping'

    missing_type = assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.load_hash({ tools: { search: {} } }, env: {})
    end
    assert_includes missing_type.message, 'must define type'

    unknown_key = assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.load_hash(
        { tools: { search: { type: 'searxng', unsupported: true } } },
        env: {},
      )
    end
    assert_includes unknown_key.message, 'Unknown tool configuration key'

    source_error = assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.new({}).load_hash(
        { tools: { search: 'invalid' } },
        source: 'tools.yml',
      )
    end
    assert_includes source_error.message, 'in tools.yml'

    source_type_error = assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.new({}).load_hash(
        { tools: { search: {} } },
        source: 'tools.yml',
      )
    end
    assert_includes source_type_error.message, 'in tools.yml'

    plural_error = assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.new({}).load_hash(
        { tools: { search: { type: 'searxng', first: true, second: true } } },
        source: 'tools.yml',
      )
    end
    assert_includes plural_error.message, 'configuration keys'
  end

  def test_load_configuration_rejects_conflicting_and_missing_tool_environment_values
    conflict = assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.load_hash(
        { tools: { search: { type: 'searxng', url: 'http://one', url_env: 'URL' } } },
        env: { 'URL' => 'http://two' },
      )
    end
    assert_includes conflict.message, 'cannot combine'

    missing = assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.load_hash(
        { tools: { search: { type: 'searxng', url_env: 'MISSING' } } },
        env: {},
      )
    end
    assert_includes missing.message, 'Environment variable not set: MISSING'

    configuration = Prescient::ConfigurationLoader.load_hash(
      {
        tools: {
          search: {
            type: 'searxng',
            url: 'http://search.local',
            timeout: '2.5',
            max_response_bytes: '1024',
            url_env: nil,
          },
        },
      },
      env: {},
    )
    assert_equal 2.5, configuration.tools[:search][:options][:timeout]
    assert_equal 1024, configuration.tools[:search][:options][:max_response_bytes]

    unknown_type = assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.new({}).load_hash(
        { tools: { search: { type: 'imaginary' } } },
        source: 'tools.yml',
      )
    end
    assert_includes unknown_type.message, 'in tools.yml'
  end
  # rubocop:enable Layout/HashAlignment, Style/BlockDelimiters, Minitest/MultipleAssertions, Minitest/AssertInDelta, Minitest/EmptyLineBeforeAssertionMethods

  def test_load_configuration_rejects_invalid_prompt_templates
    invalid_templates = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.load_hash(
        { providers: { demo: { type: 'ollama', prompt_templates: 'invalid' } } },
        env: {},
      )
    }
    assert_includes invalid_templates.message, 'must be a mapping'

    unknown_template = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.new({}).load_hash(
        {
          providers: {
            demo: {
              type:             'ollama',
              prompt_templates: { first: 'one', second: 'two' },
            },
          },
        },
        source: 'config.yml',
      )
    }
    assert_includes unknown_template.message, 'Unknown prompt template keys'
    assert_includes unknown_template.message, 'in config.yml'
  end

  def test_load_configuration_applies_direct_values_and_provider_numbers
    configuration = Prescient::ConfigurationLoader.load_yaml(<<~YAML, env: {})
      version: 1
      default_provider: ollama
      timeout: 60
      retry_attempts: 4
      retry_delay: 2.5
      fallback_providers:
        - openai
        - anthropic
      sensitive_keys:
        - workspace_secret
      providers:
        ollama:
          type: ollama
          url: http://localhost:11434
          chat_model: llama3.2:3b
          embedding_model: nomic-embed-text
          embedding_dimensions: 8
          timeout: 11
    YAML

    assert_equal :ollama, configuration.default_provider
    assert_equal 60, configuration.timeout
    assert_equal 4, configuration.retry_attempts
    assert_in_delta(2.5, configuration.retry_delay)
    assert_equal [:openai, :anthropic], configuration.fallback_providers
    assert_equal [:workspace_secret], configuration.sensitive_keys

    provider = configuration.provider(:ollama)

    assert_equal 8, provider.options[:embedding_dimensions]
    assert_equal 11, provider.options[:timeout]
  end

  def test_load_yaml_reports_source_specific_errors
    loader = Prescient::ConfigurationLoader.new({})

    syntax_error = assert_raises(Prescient::Error) {
      loader.load_yaml("version: [\n", source: 'config.yml')
    }

    assert_includes syntax_error.message, 'in config.yml'

    version_error = assert_raises(Prescient::Error) {
      loader.load_yaml("version: 2\n", source: 'config.yml')
    }

    assert_includes version_error.message, 'in config.yml'

    root_error = assert_raises(Prescient::Error) {
      loader.load_hash([], source: 'config.yml')
    }

    assert_includes root_error.message, 'in config.yml'
  end

  def test_load_configuration_rejects_unknown_keys_and_provider_types
    loader = Prescient::ConfigurationLoader.new({})

    unknown_key_error = assert_raises(Prescient::Error) {
      loader.load_yaml(<<~YAML, source: 'config.yml')
        version: 1
        unexpected: true
      YAML
    }

    assert_includes unknown_key_error.message, 'Unknown configuration key'
    assert_includes unknown_key_error.message, 'in config.yml'

    unknown_provider_error = assert_raises(Prescient::Error) {
      loader.load_yaml(<<~YAML, source: 'config.yml')
        version: 1
        providers:
          demo:
            type: imaginary
      YAML
    }

    assert_includes unknown_provider_error.message, 'Unknown provider type'
    assert_includes unknown_provider_error.message, 'in config.yml'
  end

  def test_load_configuration_rejects_conflicting_env_and_plain_values
    top_level_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.load_yaml(<<~YAML, env: {})
        version: 1
        default_provider: ollama
        default_provider_env: PRESCIENT_DEFAULT_PROVIDER
      YAML
    }

    assert_includes top_level_error.message, 'cannot combine'

    provider_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.load_yaml(<<~YAML, env: { 'OPENAI_API_KEY' => 'key' })
        version: 1
        providers:
          demo:
            type: openai
            api_key: direct
            api_key_env: OPENAI_API_KEY
            chat_model: gpt-4.1-mini
            embedding_model: text-embedding-3-small
      YAML
    }

    assert_includes provider_error.message, 'cannot combine'
  end

  def test_load_configuration_rejects_missing_environment_variables
    error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.new({}).load_yaml(<<~YAML, source: 'config.yml')
        version: 1
        timeout_env: MISSING_TIMEOUT
      YAML
    }

    assert_includes error.message, 'Environment variable not set'
    assert_includes error.message, 'in config.yml'
  end

  # rubocop:disable Minitest/MultipleAssertions
  def test_load_configuration_rejects_invalid_yaml_version_root_and_provider_shape
    invalid_yaml_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.new({}).load_yaml("version: [\n", source: 'config.yml')
    }

    assert_includes invalid_yaml_error.message, 'Invalid YAML configuration'
    assert_includes invalid_yaml_error.message, 'config.yml'

    invalid_root_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.new({}).load_hash([], source: 'config.yml')
    }

    assert_includes invalid_root_error.message, 'must be a mapping'
    assert_includes invalid_root_error.message, 'in config.yml'

    invalid_providers_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.new({}).load_yaml(<<~YAML, source: 'config.yml')
        version: 1
        providers: []
      YAML
    }

    assert_includes invalid_providers_error.message, 'providers must be a mapping'
    assert_includes invalid_providers_error.message, 'in config.yml'

    unsupported_version_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.new({}).load_yaml(<<~YAML, source: 'config.yml')
        version: 2
      YAML
    }

    assert_includes unsupported_version_error.message, 'Unsupported configuration version'
    assert_includes unsupported_version_error.message, 'in config.yml'
  end
  # rubocop:enable Minitest/MultipleAssertions

  # rubocop:disable Minitest/MultipleAssertions
  def test_load_configuration_rejects_missing_provider_type_and_file_errors
    missing_type_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.new({}).load_yaml(<<~YAML, source: 'config.yml')
        version: 1
        providers:
          demo:
            chat_model: gpt-4.1-mini
      YAML
    }

    assert_includes missing_type_error.message, 'must define type'
    assert_includes missing_type_error.message, 'in config.yml'

    provider_shape_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.new({}).load_yaml(<<~YAML, source: 'config.yml')
        version: 1
        providers:
          demo: []
      YAML
    }

    assert_includes provider_shape_error.message, 'must be a mapping'
    assert_includes provider_shape_error.message, 'in config.yml'

    unknown_provider_key_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.new({}).load_yaml(<<~YAML, source: 'config.yml')
        version: 1
        providers:
          demo:
            type: openai
            chat_model: gpt-4.1-mini
            embedding_model: text-embedding-3-small
            bogus: true
      YAML
    }

    assert_includes unknown_provider_key_error.message, 'Unknown provider configuration key'
    assert_includes unknown_provider_key_error.message, 'in config.yml'

    missing_file = Tempfile.new(['prescient-config-missing', '.yml'])
    missing_path = missing_file.path
    missing_file.close!

    file_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.load_file(missing_path, env: {})
    }

    assert_includes file_error.message, 'Configuration file not found'
  end
  # rubocop:enable Minitest/MultipleAssertions

  def test_load_configuration_rejects_null_default_provider
    error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.load_yaml(<<~YAML, env: {})
        version: 1
        default_provider: null
      YAML
    }

    assert_includes error.message, 'default_provider'
  end

  def test_load_configuration_reports_missing_interpolated_environment_variable_with_source
    error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.new({}).load_yaml(<<~YAML, source: 'config.yml')
        version: 1
        providers:
          demo:
            type: openai
            api_key: secret
            chat_model: ${MISSING_CHAT_MODEL}
            embedding_model: text-embedding-3-small
      YAML
    }

    assert_includes error.message, 'Environment variable not set'
    assert_includes error.message, 'config.yml'
  end

  def test_load_configuration_supports_array_env_references_and_string_interpolation
    env = {
      'PRESCIENT_FALLBACKS' => '[openai, anthropic]',
      'PRESCIENT_TIMEOUT'   => '33',
      'PRESCIENT_MODEL'     => 'llama3.2:3b',
    }

    configuration = Prescient::ConfigurationLoader.load_yaml(<<~YAML, env:)
      version: 1
      fallback_providers_env: PRESCIENT_FALLBACKS
      timeout_env: PRESCIENT_TIMEOUT
      providers:
        ollama:
          type: ollama
          url: http://localhost:11434
          chat_model: ${PRESCIENT_MODEL}
          embedding_model: nomic-embed-text
    YAML

    assert_equal [:openai, :anthropic], configuration.fallback_providers
    assert_equal 33, configuration.timeout
    assert_equal 'llama3.2:3b', configuration.provider(:ollama).options[:chat_model]
  end

  # rubocop:disable Minitest/MultipleAssertions
  def test_loader_covers_nested_values_coercion_and_validation_edges
    configuration = Prescient::ConfigurationLoader.load_yaml(<<~YAML, env: { 'NESTED_MODEL' => 'nested-model', 'EMPTY_VALUE' => '' })
      providers:
        ollama:
          type: ollama
          url: http://localhost:11434
          context_configs:
            document:
              fields:
                - title
              model_env: NESTED_MODEL
          chat_model: configured-model
          embedding_model: nomic-embed-text
          api_key_env:
    YAML

    assert_equal 'nested-model', configuration.provider(:ollama).options[:context_configs][:document][:model]

    empty_value_configuration = Prescient::ConfigurationLoader.load_yaml(<<~YAML, env: { 'EMPTY_VALUE' => '' })
      providers:
        ollama:
          type: ollama
          url: http://localhost:11434
          chat_model: configured-model
          embedding_model: nomic-embed-text
          api_key_env: EMPTY_VALUE
    YAML

    assert_equal '', empty_value_configuration.provider(:ollama).options[:api_key]

    integer_configuration = Prescient::ConfigurationLoader.load_hash({ timeout: 2.5 }, env: {})

    assert_equal 2, integer_configuration.timeout

    plural_key_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.load_hash({ unexpected_one: true, unexpected_two: true }, env: {})
    }
    assert_includes plural_key_error.message, 'keys'

    plural_provider_key_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.load_hash(
        { providers: { demo: { type: 'ollama', unknown_one: true, unknown_two: true } } }, env: {}
      )
    }
    assert_includes plural_provider_key_error.message, 'keys'

    nested_conflict_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.load_hash(
        { providers: { demo: { type: 'ollama', context_configs: { model: 'one', model_env: 'TWO' } } } }, env: {}
      )
    }
    assert_includes nested_conflict_error.message, 'cannot combine'

    invalid_env_name_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.load_hash({ timeout_env: nil }, env: {})
    }
    assert_includes invalid_env_name_error.message, 'Environment variable name'

    invalid_integer_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.load_hash({ timeout: 'not-an-integer' }, env: {})
    }
    assert_includes invalid_integer_error.message, 'timeout must be an integer'

    invalid_float_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.load_hash({ retry_delay: 'not-a-number' }, env: {})
    }
    assert_includes invalid_float_error.message, 'retry_delay must be a number'

    source_less_root_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.load_hash([])
    }
    refute_includes source_less_root_error.message, ' in '

    source_less_version_error = assert_raises(Prescient::Error) {
      Prescient::ConfigurationLoader.load_hash({ version: 2 })
    }
    refute_includes source_less_version_error.message, ' in '
  end
  # rubocop:enable Minitest/MultipleAssertions

  def test_loader_covers_source_less_error_messages
    assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.load_yaml("version: [\n")
    end
    assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.load_hash({ providers: [] }, env: {})
    end
    assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.load_hash({ providers: { demo: [] } }, env: {})
    end
    assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.load_hash({ providers: { demo: {} } }, env: {})
    end
    assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.load_hash({ providers: { demo: { type: 'imaginary' } } }, env: {})
    end
    assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.load_hash({ timeout_env: 'MISSING_TIMEOUT' }, env: {})
    end
    assert_raises(Prescient::Error) do
      Prescient::ConfigurationLoader.load_hash(
        { providers: { demo: { type: 'ollama', chat_model: '${MISSING_MODEL}' } } }, env: {}
      )
    end
  end

  def test_cli_supports_config_equals_and_missing_config_path
    config_path = write_configuration(<<~YAML)
      version: 1
      providers:
        ollama:
          type: ollama
          url: http://localhost:11434
          chat_model: llama3.2:3b
          embedding_model: nomic-embed-text
    YAML

    status, output, _errors = run_cli(["--config=#{config_path}", 'config', 'validate'])

    assert_equal 0, status
    assert_equal "configuration valid\n", output

    status, _output, errors = run_cli(['--config'])

    assert_equal 2, status
    assert_includes errors, 'requires a path'
  end

  def test_cli_honors_prescient_config_environment_variable
    config_path = write_configuration(<<~YAML)
      version: 1
      providers:
        ollama:
          type: ollama
          url: http://localhost:11434
          chat_model: llama3.2:3b
          embedding_model: nomic-embed-text
    YAML

    ENV['PRESCIENT_CONFIG'] = config_path

    status, output, _errors = run_cli(['config', 'validate'])

    assert_equal 0, status
    assert_equal "configuration valid\n", output
  ensure
    ENV.delete('PRESCIENT_CONFIG')
  end

  def test_schema_file_is_present_and_versioned
    schema = JSON.parse(File.read(Prescient::ConfigurationLoader.schema_path))

    assert_equal 1, schema['properties']['version']['const']
    assert_equal 'Prescient Configuration', schema['title']
  end

  private

  def write_configuration(content)
    file = Tempfile.new(['prescient-config', '.yml'])
    file.write(content)
    file.flush
    file.close
    file.path
  end

  def run_cli(arguments, input: StringIO.new)
    output = StringIO.new
    errors = StringIO.new
    status = Prescient::CLI.run(arguments, input:, output:, errors:)
    [status, output.string, errors.string]
  end
end
