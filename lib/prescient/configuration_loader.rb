# frozen_string_literal: true

require 'json'
require 'yaml'

# Load and validate Prescient configuration data from YAML.
class Prescient::ConfigurationLoader
  # Supported YAML configuration schema version.
  CONFIGURATION_VERSION = 1

  # Allowed top-level configuration keys.
  TOP_LEVEL_KEYS = [
    '$schema',
    'default_provider',
    'default_provider_env',
    'fallback_providers',
    'fallback_providers_env',
    'providers',
    'tools',
    'retry_attempts',
    'retry_attempts_env',
    'retry_delay',
    'retry_delay_env',
    'sensitive_keys',
    'sensitive_keys_env',
    'timeout',
    'timeout_env',
    'version',
  ].freeze

  # Provider names mapped to their adapter classes.
  PROVIDER_TYPES = {
    'ollama'      => Prescient::Provider::Ollama,
    'anthropic'   => Prescient::Provider::Anthropic,
    'openai'      => Prescient::Provider::OpenAI,
    'huggingface' => Prescient::Provider::HuggingFace,
    'gemini'      => Prescient::Provider::Gemini,
    'mistral'     => Prescient::Provider::Mistral,
    'deepseek'    => Prescient::Provider::DeepSeek,
    'xai'         => Prescient::Provider::XAI,
  }.freeze

  # Tool names mapped to lazily resolved adapter constants.
  TOOL_TYPES = {
    'searxng' => :SearXNG,
  }.freeze

  # Provider-specific keys shared by all supported adapters.
  COMMON_PROVIDER_KEYS = [
    'api_key',
    'api_key_env',
    'chat_model',
    'chat_model_env',
    'context_configs',
    'context_configs_env',
    'embedding_dimensions',
    'embedding_dimensions_env',
    'embedding_model',
    'embedding_model_env',
    'model',
    'model_env',
    'prompt_templates',
    'prompt_templates_env',
    'timeout',
    'timeout_env',
    'url',
    'url_env',
  ].freeze

  # Tool-specific keys accepted by all configured adapters.
  COMMON_TOOL_KEYS = [
    'categories',
    'categories_env',
    'language',
    'language_env',
    'max_response_bytes',
    'max_response_bytes_env',
    'max_results',
    'max_results_env',
    'timeout',
    'timeout_env',
    'url',
    'url_env',
  ].freeze

  # Prompt template keys supported by provider configuration.
  PROMPT_TEMPLATE_KEYS = ['system_prompt', 'no_context_template', 'with_context_template'].freeze

  # Configuration attributes supported by the loader.
  ATTR_KEYS = [
    'default_provider',
    'fallback_providers',
    'retry_attempts',
    'retry_delay',
    'sensitive_keys',
    'timeout',
  ].freeze

  class << self
    # Load and validate configuration from a YAML file.
    # @param path [String] Configuration file path
    # @param env [Hash] Environment variables used during expansion
    # @return [Prescient::Configuration] Loaded configuration
    def load_file(path, env: ENV)
      new(env).load_file(path)
    end

    # Load and validate configuration from YAML content.
    # @param content [String] YAML configuration content
    # @param env [Hash] Environment variables used during expansion
    # @return [Prescient::Configuration] Loaded configuration
    def load_yaml(content, env: ENV)
      new(env).load_yaml(content)
    end

    # Load and validate configuration from a Ruby hash.
    # @param data [Hash] Configuration data
    # @param env [Hash] Environment variables used during expansion
    # @return [Prescient::Configuration] Loaded configuration
    def load_hash(data, env: ENV)
      new(env).load_hash(data)
    end
  end

  def initialize(env = ENV)
    @env = env
  end

  # Load configuration from a YAML file.
  # @param path [String] Configuration file path
  # @return [Prescient::Configuration] Loaded configuration
  def load_file(path)
    load_yaml(File.read(path), source: path)
  rescue Errno::ENOENT
    raise Prescient::Error, "Configuration file not found: #{path}"
  end

  # Load configuration from YAML content.
  # @param content [String] YAML configuration content
  # @param source [String, nil] Source label used in validation errors
  # @return [Prescient::Configuration] Loaded configuration
  def load_yaml(content, source: nil)
    data = YAML.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: true)
    load_hash(data || {}, source:)
  rescue Psych::SyntaxError => e
    raise Prescient::Error, "Invalid YAML configuration#{" in #{source}" if source}: #{e.message}"
  end

  # Load configuration from a Ruby hash.
  # @param data [Hash] Configuration data
  # @param source [String, nil] Source label used in validation errors
  # @return [Prescient::Configuration] Loaded configuration
  def load_hash(data, source: nil)
    configuration = Prescient::Configuration.new
    Prescient.send(:configure_default_providers, configuration, @env)
    Prescient.send(:configure_default_tools, configuration, @env)
    apply!(configuration, data, source:)
    configuration
  end

  # Apply validated configuration data to an existing configuration object.
  # @param configuration [Prescient::Configuration] Target configuration
  # @param data [Hash] Configuration data
  # @param source [String, nil] Source label used in validation errors
  # @return [Prescient::Configuration] Updated configuration
  def apply!(configuration, data, source: nil)
    normalized = normalize_keys(data)
    validate_root!(normalized, source:)
    validate_version!(normalized, source:)

    apply_scalar_settings(configuration, normalized, source:)
    apply_provider_settings(configuration, normalized, source:)
    apply_tool_settings(configuration, normalized, source:)
    configuration
  end

  # Return the packaged JSON Schema path.
  # @return [String] Absolute path to the configuration schema
  def self.schema_path
    File.expand_path('../../schema/prescient.configuration.schema.json', __dir__)
  end

  private

  def validate_root!(data, source:)
    unless data.is_a?(Hash)
      raise Prescient::Error, "Configuration#{" in #{source}" if source} must be a mapping"
    end

    unknown_keys = data.keys.map(&:to_s) - TOP_LEVEL_KEYS
    return if unknown_keys.empty?

    raise Prescient::Error,
          "Unknown configuration key#{'s' if unknown_keys.length > 1}: #{unknown_keys.join(', ')}" \
          "#{" in #{source}" if source}"
  end

  def apply_scalar_settings(configuration, data, source:)
    apply_default_provider(configuration, data, source:)
    apply_numeric_settings(configuration, data, source:)
    apply_collection_settings(configuration, data, source:)
  end

  def apply_default_provider(configuration, data, source:)
    return unless scalar_present?(data, :default_provider)

    default_provider = resolve_scalar(data, :default_provider, source:)
    if default_provider.nil? || default_provider.to_s.empty?
      raise Prescient::Error, 'default_provider must be a non-empty string'
    end

    configuration.default_provider = default_provider.to_sym
  end

  def apply_numeric_settings(configuration, data, source:)
    numeric_settings = {
      timeout:        [:coerce_integer, 'timeout'],
      retry_attempts: [:coerce_integer, 'retry_attempts'],
      retry_delay:    [:coerce_float, 'retry_delay'],
    }

    numeric_settings.each do |key, (coercer, name)|
      next unless scalar_present?(data, key)

      value = resolve_scalar(data, key, source:)
      setter = "#{key}="
      configuration.public_send(setter, send(coercer, value, name))
    end
  end

  def apply_collection_settings(configuration, data, source:)
    if scalar_present?(data, :fallback_providers)
      value = resolve_scalar(data, :fallback_providers, source:)
      configuration.fallback_providers = Array(value).map(&:to_sym)
    end

    return unless scalar_present?(data, :sensitive_keys)

    configuration.sensitive_keys = Array(resolve_scalar(data, :sensitive_keys, source:))
  end

  def apply_provider_settings(configuration, data, source:)
    return unless key_present?(data, :providers)

    providers = data[:providers]
    unless providers.is_a?(Hash)
      raise Prescient::Error, "Configuration#{" in #{source}" if source} providers must be a mapping"
    end

    providers.each do |name, provider_data|
      provider_name = name.to_sym
      provider_settings = normalize_keys(provider_data)
      validate_provider!(provider_name, provider_settings, source:)

      provider_options = resolve_provider_options(provider_settings, source:)
      configuration.add_provider(provider_name, PROVIDER_TYPES[provider_settings.fetch(:type).to_s],
                                 **provider_options)
    end
  end

  def apply_tool_settings(configuration, data, source:)
    return unless key_present?(data, :tools)

    tools = data[:tools]
    unless tools.is_a?(Hash)
      raise Prescient::Error, "Configuration#{" in #{source}" if source} tools must be a mapping"
    end

    tools.each do |name, tool_data|
      tool_name = name.to_sym
      tool_settings = normalize_keys(tool_data)
      validate_tool!(tool_name, tool_settings, source:)

      tool_options = resolve_tool_options(tool_settings, source:)
      configuration.add_tool(tool_name, tool_class_for(tool_settings.fetch(:type).to_s), **tool_options)
    end
  end

  def validate_provider!(name, provider_data, source:)
    validate_provider_shape!(name, provider_data, source:)
    validate_provider_type!(name, provider_data, source:)
    validate_provider_keys!(name, provider_data, source:)
    validate_prompt_templates!(name, provider_data, source:)
  end

  def validate_provider_shape!(name, provider_data, source:)
    return if provider_data.is_a?(Hash)

    raise Prescient::Error, "Provider #{name.inspect}#{" in #{source}" if source} must be a mapping"
  end

  def validate_provider_type!(name, provider_data, source:)
    return if provider_data.key?(:type)

    raise Prescient::Error, "Provider #{name}#{" in #{source}" if source} must define type"
  end

  def validate_provider_keys!(name, provider_data, source:)
    unknown_keys = provider_data.keys.map(&:to_s) - (['type'] + COMMON_PROVIDER_KEYS)
    return if unknown_keys.empty?

    raise Prescient::Error,
          "Unknown provider configuration key#{'s' if unknown_keys.length > 1} for #{name}: " \
          "#{unknown_keys.join(', ')}" \
          "#{" in #{source}" if source}"
  end

  def validate_prompt_templates!(name, provider_data, source:)
    templates = provider_data[:prompt_templates]
    return if templates.nil?

    source_suffix = " in #{source}" if source
    unless templates.is_a?(Hash)
      raise Prescient::Error, "prompt_templates for #{name} must be a mapping#{source_suffix}"
    end

    unknown_keys = templates.keys.map(&:to_s) - PROMPT_TEMPLATE_KEYS
    return if unknown_keys.empty?

    message = "Unknown prompt template key#{'s' if unknown_keys.length > 1} for #{name}: " \
              "#{unknown_keys.join(', ')}#{source_suffix}"
    raise Prescient::Error, message
  end

  def validate_tool!(name, tool_data, source:)
    validate_tool_shape!(name, tool_data, source:)
    validate_tool_type!(name, tool_data, source:)
    validate_tool_keys!(name, tool_data, source:)
  end

  def validate_tool_shape!(name, tool_data, source:)
    return if tool_data.is_a?(Hash)

    raise Prescient::Error, "Tool #{name.inspect}#{" in #{source}" if source} must be a mapping"
  end

  def validate_tool_type!(name, tool_data, source:)
    return if tool_data.key?(:type)

    raise Prescient::Error, "Tool #{name}#{" in #{source}" if source} must define type"
  end

  def validate_tool_keys!(name, tool_data, source:)
    unknown_keys = tool_data.keys.map(&:to_s) - (['type'] + COMMON_TOOL_KEYS)
    return if unknown_keys.empty?

    raise Prescient::Error,
          "Unknown tool configuration key#{'s' if unknown_keys.length > 1} for #{name}: " \
          "#{unknown_keys.join(', ')}" \
          "#{" in #{source}" if source}"
  end

  def resolve_provider_options(provider_data, source:)
    provider_type = provider_data[:type].to_s
    provider_class = PROVIDER_TYPES[provider_type]
    unless provider_class
      raise Prescient::Error,
            "Unknown provider type #{provider_type.inspect}#{" in #{source}" if source}"
    end

    provider_data.each_with_object({}) do |(key, value), options|
      option = resolve_provider_option(provider_data, key, value, source:)
      options[option.first] = option.last if option
    end
  end

  def resolve_tool_options(tool_data, source:)
    tool_type = tool_data[:type].to_s
    tool_class = tool_class_for(tool_type)
    unless tool_class
      raise Prescient::Error,
            "Unknown tool type #{tool_type.inspect}#{" in #{source}" if source}"
    end

    tool_data.each_with_object({}) do |(key, value), options|
      option = resolve_tool_option(tool_data, key, value, source:)
      options[option.first] = option.last if option
    end
  end

  # Resolve a configured tool adapter only when configuration uses it.
  # @param tool_type [String] Configured tool type
  # @return [Class, nil] Tool adapter class
  def tool_class_for(tool_type)
    tool_name = TOOL_TYPES[tool_type]
    return unless tool_name

    Prescient::Tool.const_get(tool_name, false)
  end

  def resolve_tool_option(tool_data, key, value, source:)
    return if key == :type
    return if key.to_s.end_with?('_env') && value.nil?

    if key.to_s.end_with?('_env')
      base_key = key.to_s.delete_suffix('_env').to_sym
      if tool_data.key?(base_key)
        raise Prescient::Error,
              "Tool configuration cannot combine #{base_key} and #{key}"
      end

      [base_key, resolve_env_value(value, source:)]
    else
      [key, coerce_tool_option(key, resolve_value(value, source:))]
    end
  end

  def resolve_provider_option(provider_data, key, value, source:)
    return if key == :type
    return if key.to_s.end_with?('_env') && value.nil?

    if key.to_s.end_with?('_env')
      base_key = key.to_s.delete_suffix('_env').to_sym
      if provider_data.key?(base_key)
        raise Prescient::Error,
              "Provider configuration cannot combine #{base_key} and #{key}"
      end

      [base_key, resolve_env_value(value, source:)]
    else
      [key, coerce_provider_option(key, resolve_value(value, source:))]
    end
  end

  def resolve_scalar(data, key, source:)
    env_key = :"#{key}_env"
    if key_present?(data, key) && key_present?(data, env_key)
      raise Prescient::Error, "Configuration cannot combine #{key} and #{key}_env"
    end

    return resolve_env_value(data[env_key], source:) if key_present?(data, env_key)

    value = data[key]
    return nil if value.nil?

    resolve_value(value, source:)
  end

  def resolve_value(value, source:)
    case value
    when Hash
      resolve_hash_value(value, source:)
    when Array
      value.map { |item| resolve_value(item, source:) }
    when String
      interpolate_env(value, source:)
    else
      value
    end
  end

  def resolve_hash_value(value, source:)
    value.each_with_object({}) do |(key, nested_value), result|
      key_name = key.to_s
      if key_name.end_with?('_env')
        base_key = key_name.delete_suffix('_env').to_sym
        if value.key?(base_key) || value.key?(base_key.to_s)
          raise Prescient::Error, "Configuration cannot combine #{base_key} and #{key_name}"
        end

        result[base_key] = resolve_env_value(nested_value, source:)
      else
        result[key.to_sym] = resolve_value(nested_value, source:)
      end
    end
  end

  def resolve_env_value(value, source:)
    env_name = resolve_value(value, source:)
    unless env_name.is_a?(String) && !env_name.empty?
      raise Prescient::Error, 'Environment variable name must be a non-empty string'
    end

    raw_value = @env.fetch(env_name)
    parsed_value = YAML.safe_load(raw_value, permitted_classes: [], permitted_symbols: [], aliases: true)
    parsed_value.nil? ? raw_value : parsed_value
  rescue KeyError
    raise Prescient::Error, "Environment variable not set: #{env_name}#{" in #{source}" if source}"
  end

  def interpolate_env(value, source:)
    value.gsub(/\$\{([A-Z0-9_]+)\}/) do
      env_name = Regexp.last_match(1)
      @env.fetch(env_name)
    rescue KeyError
      raise Prescient::Error, "Environment variable not set: #{env_name}#{" in #{source}" if source}"
    end
  end

  def normalize_keys(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested_value), result|
        result[key.to_sym] = normalize_keys(nested_value)
      end
    when Array
      value.map { |item| normalize_keys(item) }
    else
      value
    end
  end

  def key_present?(data, key)
    data.key?(key) || data.key?(key.to_s)
  end

  def scalar_present?(data, key)
    key_present?(data, key) || key_present?(data, :"#{key}_env")
  end

  def coerce_integer(value, name)
    return value if value.is_a?(Integer)
    return value.to_i if value.is_a?(Numeric)

    Integer(value)
  rescue ArgumentError, TypeError
    raise Prescient::Error, "#{name} must be an integer"
  end

  def coerce_float(value, name)
    return value.to_f if value.is_a?(Numeric)

    Float(value)
  rescue ArgumentError, TypeError
    raise Prescient::Error, "#{name} must be a number"
  end

  def coerce_provider_option(key, value)
    case key.to_sym
    when :embedding_dimensions
      coerce_integer(value, 'embedding_dimensions')
    when :timeout
      coerce_integer(value, 'timeout')
    else
      value
    end
  end

  def coerce_tool_option(key, value)
    case key.to_sym
    when :max_results, :max_response_bytes
      coerce_integer(value, key.to_s)
    when :timeout
      coerce_float(value, 'timeout')
    else
      value
    end
  end

  def validate_version!(data, source:)
    return unless key_present?(data, :version)

    version = resolve_value(data[:version], source:)
    return if version == CONFIGURATION_VERSION

    raise Prescient::Error,
          "Unsupported configuration version #{version.inspect}#{" in #{source}" if source}"
  end
end
