# frozen_string_literal: true

require 'json'
require 'optparse'

# Command-line interface for common Prescient operations.
class Prescient::CLI
  # Supported output formats.
  # @return [Array<String>] Output format names
  FORMATS = ['text', 'json'].freeze

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

  def run
    command = @arguments.shift
    return print_help(2) unless command

    case command
    when 'providers' then providers
    when 'health' then health
    when 'generate' then generate
    when 'embed' then embed
    when 'config' then config
    when 'help', '--help', '-h' then print_help(0)
    else
      raise UsageError, "unknown command #{command.inspect}; run 'prescient help'"
    end
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
    options = parse_options('Generate a text response', fallback: true)
    return options if options.is_a?(Integer)

    prompt = read_text(options[:arguments], 'prompt')
    client = client_for(options)
    response = client.generate_response(prompt, **model_options(options))

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

  def config
    subcommand = @arguments.shift
    raise UsageError, "unknown config command #{subcommand.inspect}" unless subcommand == 'validate'

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

  def validate_configuration
    configuration = Prescient.configuration
    unless configuration.provider(configuration.default_provider)
      raise Prescient::Error, 'default provider is not configured'
    end

    configuration.providers.each_key { |name| configuration.provider(name) }
  end

  def parse_options(description, fallback: false)
    options = { format: 'text', fallback: fallback }
    parser = OptionParser.new do |parser|
      parser.banner = "Usage: prescient #{@arguments.first || 'command'} [options]"
      parser.separator description
      add_common_options(parser, options)
      parser.on('--no-fallback', 'Disable provider fallback') { options[:fallback] = false } if fallback
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

  def add_common_options(parser, options)
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
  end

  def add_credential_options(parser, options)
    parser.on('--api-key KEY', 'Use an API key for this operation') do |value|
      options[:api_key] = value
    end
    parser.on('--api-key-env NAME', 'Read the API key from this environment variable') do |value|
      options[:api_key_env] = value
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
      api_key:         api_key_override(options),
      embedding_model: options[:embedding_model],
      chat_model:      options[:chat_model],
    }.compact
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
        config validate Validate the current configuration

      Options:
        --provider NAME          Select a provider
        --model NAME             Override the selected operation's model
        --chat-model NAME        Override the chat model
        --embedding-model NAME   Override the embedding model
        --api-key KEY            Use an API key for the operation
        --api-key-env NAME       Read the API key from an environment variable
        --format FORMAT          Use text or json output
    HELP
    status
  end
end
