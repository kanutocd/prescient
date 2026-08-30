# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::Agent
  # Runs a bounded single-agent tool-calling loop through Prescient::Client.
  class Runtime
    def initialize(provider: nil, client: nil, tools: nil, tool_names: [], configuration: Configuration.new,
                   system_prompt: 'You are a helpful assistant.')
      @client = client || Prescient.client(provider, enable_fallback: true)
      configured_tools = tools || tool_names.to_h { |name| [name, Prescient.tool(name)] }
      configured_tools = configured_tools.compact
      @registry = ToolRegistry.new(configured_tools)
      @configuration = configuration
      @system_prompt = system_prompt
    end

    def run(task)
      validate_task(task)
      context = build_context(task)

      @configuration.max_loops.times do |index|
        response = @client.generate_response(task, context.to_a)
        return result(response, index + 1) unless action_appended?(context, response)
      end

      raise MaxLoopsExceededError, "agent exceeded maximum loops: #{@configuration.max_loops}"
    end

    private

    def build_context(task)
      Context.new(
        system_prompt: PromptBuilder.build(system_instruction: @system_prompt, tools: @registry.all),
        task:          task,
        max_bytes:     @configuration.max_context_bytes,
      )
    end

    def action_appended?(context, response)
      action = Parser.parse(response[:response], max_bytes: @configuration.max_action_bytes)
      return false unless action

      observation = @registry.invoke(action[:name], action[:arguments])
      observation_text = JSON.generate(observation).byteslice(0, @configuration.max_observation_bytes)
      context.append(role: 'assistant', content: response[:response])
      context.append(role: 'user', content: "Observation: #{observation_text}")
      true
    end

    def validate_task(task)
      return if task.is_a?(String) && !task.strip.empty?

      raise ConfigurationError, 'agent task must be a non-empty string'
    end

    def result(response, loops_run)
      Result.new(
        response:  response[:response],
        provider:  response[:provider] || @client.provider_name,
        model:     response[:model],
        loops_run: loops_run,
      )
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
