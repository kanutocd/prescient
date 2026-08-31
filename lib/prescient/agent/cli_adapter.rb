# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::Agent
  # Adapts the bounded agent runtime to CLI streams and exit statuses.
  class CLIAdapter
    def initialize(output: $stdout, errors: $stderr)
      @output = output
      @errors = errors
    end

    # Run an agent task and render a text or JSON result.
    # @return [Integer] Process exit status
    def run(task:, client: nil, provider: nil, tool_names: [], max_loops: Configuration::DEFAULT_MAX_LOOPS,
            format: "text", provider_options: {}, generation_options: {}, telemetry: nil)
      runtime = Runtime.new(
        client:, provider:, tool_names:, configuration: Configuration.new(max_loops:, telemetry:),
        provider_options:, generation_options:
      )
      result = runtime.run(task)
      format == "json" ? @output.puts(JSON.generate(result.to_h)) : @output.puts(result.response)
      0
    rescue Prescient::Error, ArgumentError => e
      @errors.puts "prescient: #{e.message}"
      1
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
