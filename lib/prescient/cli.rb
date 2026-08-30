# frozen_string_literal: true

require 'json'
require 'optparse'
require 'yaml'
require_relative '../prescient'

# Command-line interface for common Prescient operations.
class Prescient::CLI
  # @return [Hash<String, Symbol>] CLI command dispatch table
  COMMAND_HANDLERS = {
    'providers' => :providers,
    'health'    => :health,
    'generate'  => :generate,
    'embed'     => :embed,
    'search'    => :search,
    'agent'     => :agent,
    'config'    => :config,
  }.freeze
  # Supported output formats.
  # @return [Array<String>] Output format names
  FORMATS = ['text', 'json'].freeze

  # Schema URL and annotated starter configuration for `config example`.
  CONFIGURATION_EXAMPLE = <<~YAML
    # yaml-language-server: $schema=https://raw.githubusercontent.com/kanutocd/prescient/refs/heads/main/schema/prescient.configuration.schema.json
    #
    # Prescient configuration example.
    #
    # Precedence, from lowest to highest:
    # 1. Built-in defaults and provider environment variables.
    # 2. Values in this YAML file.
    # 3. Per-operation CLI overrides such as --provider and --chat-model.
    #
    # Use `prescient config validate` after editing this file.
    # Keep credentials out of source control; use *_env references instead.
    version: 1

    # Global behavior.
    default_provider: ollama
    timeout: 30
    retry_attempts: 3
    retry_delay: 1.0
    fallback_providers: []
    sensitive_keys:
      - api_key
      - password
      - token
      - secret

    providers:
      # Local Ollama requires no API key.
      ollama:
        type: ollama
        url: http://localhost:11434
        embedding_model: nomic-embed-text
        chat_model: llama3.2:3b
        # prompt_templates:
        #   system_prompt: You are a concise assistant.
        #   no_context_template: "%<system_prompt>s\x5Cn\x5CnUser: %<query>s"
        #   with_context_template: "%<system_prompt>s\x5Cn\x5CnContext:\x5Cn%<context>s\x5Cn\x5CnUser: %<query>s"

      # Uncomment a cloud provider and set its credential in the environment.
      # openai:
      #   type: openai
      #   api_key_env: OPENAI_API_KEY
      #   embedding_model: text-embedding-3-small
      #   chat_model: gpt-4.1-mini
      #   prompt_templates:
      #     system_prompt: You are a concise assistant.
      #     no_context_template: "%<system_prompt>s\x5Cn\x5CnUser: %<query>s"

      # anthropic:
      #   type: anthropic
      #   api_key_env: ANTHROPIC_API_KEY
      #   model: claude-sonnet-4-20250514

      # gemini:
      #   type: gemini
      #   api_key_env: GEMINI_API_KEY
      #   embedding_model: gemini-embedding-001
      #   chat_model: gemini-2.5-flash

      # mistral:
      #   type: mistral
      #   api_key_env: MISTRAL_API_KEY
      #   embedding_model: mistral-embed
      #   chat_model: mistral-large-latest

      # DeepSeek supports text generation, but not embeddings.
      # deepseek:
      #   type: deepseek
      #   api_key_env: DEEPSEEK_API_KEY
      #   chat_model: deepseek-v4-flash

      # xai:
      #   type: xai
      #   api_key_env: XAI_API_KEY
      #   chat_model: grok-4.5

      # huggingface:
      #   type: huggingface
      #   api_key_env: HUGGINGFACE_API_KEY
      #   embedding_model: sentence-transformers/all-MiniLM-L6-v2
      #   chat_model: google/gemma-2-2b-it

    # External tools are opt-in and separate from AI providers. They can be
    # used directly with `prescient search`, or as context with
    # `prescient search --generate`.
    #
    # The CLI also registers `web_search` automatically when SEARXNG_URL is
    # set and no YAML tool configuration is provided.
    tools:
      # Local SearXNG example. Uncomment this block to configure a tool in YAML.
      # web_search:
      #   type: searxng
      #   url: http://localhost:8080
      #   timeout: 5
      #   max_results: 5
      #   language: en
      #   categories:
      #     - general
      #     - science
      #   max_response_bytes: 1048576

      # SearchApi example. It uses SearchApi's Google engine by default and
      # authenticates with a Bearer token from the environment.
      # searchapi_web:
      #   type: searchapi
      #   api_key_env: SEARCHAPI_API_KEY
      #   engine: google
      #   location: New York
      #   hl: en
      #   gl: us
      #   timeout: 10
      #   max_results: 5

      # Capability fallback. Adapters are tried in order, and fallback occurs
      # only for transient connection or rate-limit failures.
      # resilient_search:
      #   adapters:
      #     - type: searxng
      #       url_env: SEARXNG_URL
      #     - type: searchapi
      #       api_key_env: SEARCHAPI_API_KEY
      #       engine: google

      # Prefer an environment reference when the URL differs by environment
      # or should not be committed. Use `--tool research_search` to select a
      # tool with a custom name.
      # research_search:
      #   type: searxng
      #   url_env: SEARXNG_URL
      #   timeout_env: SEARXNG_TIMEOUT
      #   max_results_env: SEARXNG_MAX_RESULTS
      #   language_env: SEARXNG_LANGUAGE
      #   categories_env: SEARXNG_CATEGORIES

      # Search results are returned directly by default. Add `--generate` to
      # feed normalized results to the selected AI provider. Omit `--generate`
      # when the caller should handle the search results itself.
  YAML

  # Raised when command-line arguments are invalid or incomplete.
  class UsageError < StandardError; end

  # Run the CLI and return a process exit status.
  #
  # @param arguments [Array<String>] Command-line arguments
  # @param input [IO] Input stream used for stdin prompts
  # @param output [IO] Output stream for command results
  # @param errors [IO] Output stream for diagnostics
  # @return [Integer] Process exit status
  def self.run(arguments, input: $stdin, output: $stdout, errors: $stderr)
    new(arguments, input:, output:, errors:).run
  rescue UsageError, OptionParser::ParseError => e
    errors.puts "prescient: #{e.message}"
    2
  rescue Prescient::Error => e
    errors.puts "prescient: #{e.message}"
    1
  end

  # Initialize a CLI runner with injectable streams.
  #
  # @param arguments [Array<String>] Command-line arguments
  # @param input [IO] Input stream used for stdin prompts
  # @param output [IO] Output stream for command results
  # @param errors [IO] Output stream for diagnostics
  def initialize(arguments, input:, output:, errors:)
    @arguments = arguments.dup
    @input = input
    @output = output
    @errors = errors
  end

  # Execute the CLI command and return its process status.
  # @return [Integer] Process exit status
  def run
    config_path = extract_global_config_path
    Prescient.load_configuration(config_path) if config_path || ENV['PRESCIENT_CONFIG']

    command = @arguments.shift
    return print_help(2) unless command

    run_command(command)
  end

  # Dispatch a parsed command to its handler.
  # @param command [String] Command name
  # @return [Integer] Process exit status
  def run_command(command)
    return print_help(0) if ['help', '--help', '-h'].include?(command)

    handler = COMMAND_HANDLERS[command]
    raise UsageError, "unknown command #{command.inspect}; run 'prescient help'" unless handler

    send(handler)
  end

  private

  def providers
    options = parse_options('List configured providers')
    return options if options.is_a?(Integer)

    provider_list = Prescient.configuration.providers.map { |name, registration|
      { name: name.to_s, class: registration[:class].name }
    }

    if options[:format] == 'json'
      print_json(providers: provider_list)
    else
      provider_list.each { |provider| @output.puts "#{provider[:name]}\t#{provider[:class]}" }
    end
    0
  end

  def health
    options = parse_options('Check provider health')
    return options if options.is_a?(Integer)

    names = options[:provider] ? [options[:provider].to_sym] : Prescient.configuration.providers.keys
    raise UsageError, 'no providers are configured' if names.empty?

    results = names.to_h { |name| [name.to_s, Prescient.health_check(provider: name)] }
    output_health(results, options[:format])
    results.values.all? { |result| result[:reachable] != false } ? 0 : 1
  end

  def generate
    options = parse_options('Generate a text response', fallback: true, documents: true)
    return options if options.is_a?(Integer)

    prompt = read_text(options[:arguments], 'prompt')
    client = client_for(options)
    context = if options[:json_file]
                Prescient::DocumentSource::JsonFile.new(path: options[:json_file]).fetch
              else
                []
              end
    response = client.generate_response(prompt, context, **model_options(options))

    options[:format] == 'json' ? print_json(response) : @output.puts(response[:response])
    0
  end

  def embed
    options = parse_options('Generate an embedding', fallback: true)
    return options if options.is_a?(Integer)

    text = read_text(options[:arguments], 'text')
    client = client_for(options)
    embedding = client.generate_embedding(text, **model_options(options))

    if options[:format] == 'json'
      print_json(embedding: embedding, dimensions: embedding.length, provider: client.provider_name.to_s)
    else
      @output.puts JSON.generate(embedding)
    end
    0
  end

  def search
    options = parse_options(
      'Search with a configured external tool',
      fallback: true, tool: true, limit: true, generate: true,
    )
    return options if options.is_a?(Integer)

    query = read_text(options[:arguments], 'query')
    tool_name = (options[:tool] || 'web_search').to_sym
    return generate_search_response(query, tool_name, options) if options[:generate]

    tool = Prescient.tool(tool_name)
    raise UsageError, "tool not configured: #{tool_name}" unless tool

    result = tool.search(query, limit: options[:limit])
    if options[:format] == 'json'
      print_json(result)
    else
      print_search_results(result[:results])
    end
    0
  end

  def agent
    require 'prescient/agent'
    options = parse_options('Run a bounded agent task', agent: true)
    return options if options.is_a?(Integer)

    task = read_text(options[:arguments], 'task')
    runtime = agent_runtime(options)
    result = runtime.run(task)
    options[:format] == 'json' ? print_json(result.to_h) : @output.puts(result.response)
    0
  end

  def agent_runtime(options)
    configuration = Prescient::Agent::Configuration.new(max_loops: options[:max_loops] || 5)
    Prescient::Agent::Runtime.new(
      provider:           options[:provider]&.to_sym,
      client:             client_for(options),
      tool_names:         options.fetch(:tools, []),
      configuration:      configuration,
      provider_options:   provider_options(options),
      generation_options: model_options(options),
    )
  end

  def generate_search_response(query, tool_name, options)
    response = Prescient.search_and_generate(
      query,
      tool:             tool_name,
      provider:         options[:provider]&.to_sym,
      limit:            options[:limit],
      enable_fallback:  options[:fallback],
      provider_options: provider_options(options),
      **model_options(options),
    )
    options[:format] == 'json' ? print_json(response) : @output.puts(response[:response])
    0
  end

  def print_search_results(results)
    results.each do |item|
      @output.puts item[:title]
      @output.puts item[:url]
      @output.puts item[:snippet] unless item[:snippet].empty?
      @output.puts
    end
  end

  def config
    subcommand = @arguments.shift
    case subcommand
    when 'validate' then validate_config_command
    when 'example' then configuration_example_command
    else
      raise UsageError, "unknown config command #{subcommand.inspect}"
    end
  end

  def validate_config_command
    options = parse_options('Validate the current configuration')
    return options if options.is_a?(Integer)

    validate_configuration
    if options[:format] == 'json'
      print_json(valid: true, providers: Prescient.configuration.providers.keys.map(&:to_s))
    else
      @output.puts 'configuration valid'
    end
    0
  end

  def configuration_example_command
    options = parse_options('Generate an annotated YAML configuration example')
    return options if options.is_a?(Integer)

    @output.write(CONFIGURATION_EXAMPLE)
    0
  end

  def validate_configuration
    configuration = Prescient.configuration
    unless configuration.provider(configuration.default_provider)
      raise Prescient::Error, 'default provider is not configured'
    end

    configuration.providers.each_key do |name|
      configuration.provider(name)
    end
    configuration.tools.each_key do |name|
      configuration.tool(name)
    end
  end

  def parse_options(description, fallback: false, tool: false, limit: false, generate: false,
                    documents: false, agent: false)
    options = { format: 'text', fallback: fallback }
    parser = OptionParser.new do |parser|
      parser.banner = "Usage: prescient #{@arguments.first || 'command'} [options]"
      parser.separator description
      parser.separator ''
      parser.separator 'Global options:'
      add_common_options(parser, options)
      add_optional_options(parser, options, fallback:, tool:, limit:, generate:, documents:, agent:)
      parser.on('-h', '--help', 'Show command help') do
        @output.puts parser
        throw :help_shown, 0
      end
    end

    result = catch(:help_shown) { parse_arguments(parser) }
    return result unless result.nil?

    options[:arguments] = @arguments
    options
  end

  def add_optional_options(parser, options, fallback:, tool:, limit:, generate:, documents:, agent:)
    add_document_options(parser, options) if documents
    parser.on('--no-fallback', 'Disable provider fallback') { options[:fallback] = false } if fallback
    add_tool_options(parser, options, tool:, limit:, generate:)
    add_agent_options(parser, options) if agent
  end

  def add_agent_options(parser, options)
    parser.separator ''
    parser.separator 'Agent options:'
    options[:tools] = []
    parser.on('--tool NAME', 'Allow a configured tool (repeatable)') do |value|
      options[:tools] << value.to_sym
    end
    parser.on('--max-loops COUNT', Integer, 'Maximum agent iterations') { |value| options[:max_loops] = value }
  end

  def add_tool_options(parser, options, tool:, limit:, generate:)
    return unless tool || limit || generate

    parser.separator ''
    parser.separator 'Search options:'
    parser.on('--tool NAME', 'Use a configured external tool') { |value| options[:tool] = value } if tool
    parser.on('--generate', 'Use search results as AI provider context') { options[:generate] = true } if generate
    return unless limit

    parser.on('--limit COUNT', Integer, 'Limit the number of results') { |value| options[:limit] = value }
  end

  def add_common_options(parser, options)
    parser.on('--config PATH', 'Load configuration from a YAML file') do |value|
      options[:config] = value
    end
    parser.on('--format FORMAT', FORMATS, "Output format (#{FORMATS.join(', ')})") do |value|
      options[:format] = value
    end
    parser.on('--provider NAME', 'Use a specific provider') do |value|
      options[:provider] = value
    end
    add_model_options(parser, options)
    add_credential_options(parser, options)
  end

  # Parse command arguments and return nil when parsing completes.
  #
  # @param parser [OptionParser] Configured command option parser
  # @return [nil]
  def parse_arguments(parser)
    parser.parse!(@arguments)
    nil
  end

  def model_options(options)
    options[:model] ? { model: options[:model] } : {}
  end

  def client_for(options)
    validate_override_options(options)
    Prescient.client(
      options[:provider]&.to_sym,
      enable_fallback:  options[:fallback],
      provider_options: provider_options(options),
    )
  rescue KeyError => e
    raise UsageError, "environment variable not set: #{e.key}"
  end

  def add_model_options(parser, options)
    parser.on('--model NAME', 'Override the configured model') do |value|
      options[:model] = value
    end
    parser.on('--embedding-model NAME', 'Override the embedding model') do |value|
      options[:embedding_model] = value
    end
    parser.on('--chat-model NAME', 'Override the chat model') do |value|
      options[:chat_model] = value
    end
    parser.on('--system-prompt TEXT', 'Override the system prompt') do |value|
      options[:system_prompt] = value
    end
    parser.on('--no-context-template TEXT', 'Override the no-context prompt template') do |value|
      options[:no_context_template] = value
    end
    parser.on('--with-context-template TEXT', 'Override the with-context prompt template') do |value|
      options[:with_context_template] = value
    end
    parser.on('--prompt-templates-file PATH', 'Load prompt templates from a YAML file') do |value|
      options[:prompt_templates_file] = value
    end
  end

  def add_credential_options(parser, options)
    parser.on('--api-key KEY', 'Use an API key for this operation') do |value|
      options[:api_key] = value
    end
    parser.on('--api-key-env NAME', 'Read the API key from this environment variable') do |value|
      options[:api_key_env] = value
    end
  end

  def add_document_options(parser, options)
    parser.on('--json-file PATH', 'Load JSON documents as generation context') do |value|
      options[:json_file] = value
    end
  end

  def validate_override_options(options)
    if options[:model] && (options[:embedding_model] || options[:chat_model])
      raise UsageError, '--model cannot be combined with --embedding-model or --chat-model'
    end
    return unless options[:api_key] && options[:api_key_env]

    raise UsageError, '--api-key cannot be combined with --api-key-env'
  end

  def provider_options(options)
    {
      api_key:          api_key_override(options),
      embedding_model:  options[:embedding_model],
      chat_model:       options[:chat_model],
      prompt_templates: prompt_templates(options),
    }.compact
  end

  def prompt_templates(options)
    templates = if options[:prompt_templates_file]
                  data = YAML.safe_load_file(
                    options[:prompt_templates_file],
                    permitted_classes: [],
                    permitted_symbols: [],
                    aliases:           true,
                  )
                  raise UsageError, 'prompt templates file must contain a mapping' unless data.is_a?(Hash)

                  data.transform_keys(&:to_sym)
                else
                  {}
                end

    [:system_prompt, :no_context_template, :with_context_template].each do |key|
      templates[key] = options[key] if options[key]
    end
    templates.empty? ? nil : templates
  rescue Errno::ENOENT
    raise UsageError, "prompt templates file not found: #{options[:prompt_templates_file]}"
  rescue Psych::SyntaxError => e
    raise UsageError, "invalid prompt templates YAML: #{e.message}"
  end

  def api_key_override(options)
    return options[:api_key] if options[:api_key]
    return ENV.fetch(options[:api_key_env]) if options[:api_key_env]

    nil
  end

  def output_health(results, format)
    if format == 'json'
      print_json(results)
    else
      results.each do |name, result|
        @output.puts '%<name>-12s %<status>s' % { name: name, status: result[:status] || 'unknown' }
      end
    end
  end

  def read_text(arguments, label)
    return arguments.join(' ') unless arguments.empty?
    return @input.read unless @input.tty?

    raise UsageError, "missing #{label}; provide it as an argument or through stdin"
  end

  def print_json(value)
    @output.puts JSON.generate(value)
  end

  def print_help(status)
    @output.puts <<~HELP
      Usage: prescient COMMAND [options]

      Commands:
        providers       List configured providers
        health          Check provider health
        generate TEXT   Generate a text response
        embed TEXT      Generate an embedding
        search TEXT     Search with a configured external tool
        agent TEXT       Run a bounded agent task
        config validate Validate the current configuration
        config example  Generate an annotated YAML configuration example

      Global options:
        --config PATH            Load configuration from a YAML file
        --provider NAME          Select a provider
        --model NAME             Override the selected operation's model
        --chat-model NAME        Override the chat model
        --embedding-model NAME   Override the embedding model
        --system-prompt TEXT     Override the system prompt
        --no-context-template TEXT
                                 Override the no-context prompt template
        --with-context-template TEXT
                                 Override the with-context prompt template
        --prompt-templates-file PATH
                                 Load prompt templates from a YAML file
        --api-key KEY            Use an API key for the operation
        --api-key-env NAME       Read the API key from an environment variable
        --format FORMAT          Use text or json output
        --json-file PATH         Load JSON documents as generation context

      Search options:
        --tool NAME              Select an external tool for search
        --generate               Use search results as AI provider context
        --limit COUNT            Limit search results

      Agent options:
        --tool NAME              Allow a configured tool (repeatable)
        --max-loops COUNT        Maximum agent iterations
    HELP
    status
  end

  def extract_global_config_path
    config_path = nil
    filtered_arguments = []
    index = 0

    while index < @arguments.length
      argument = @arguments[index]
      if argument == '--config'
        value = @arguments[index + 1]
        raise UsageError, '--config requires a path' unless value

        config_path = value
        index += 2
        next
      end

      if argument.start_with?('--config=')
        config_path = argument.split('=', 2).last
        index += 1
        next
      end

      filtered_arguments << argument
      index += 1
    end

    @arguments = filtered_arguments
    config_path
  end
end
