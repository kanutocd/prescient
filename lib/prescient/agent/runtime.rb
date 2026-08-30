# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::Agent
  # Runs a bounded single-agent tool-calling loop through Prescient::Client.
  class Runtime
    def initialize(provider: nil, client: nil, tools: nil, tool_names: [], configuration: Configuration.new,
                   system_prompt: 'You are a helpful assistant.', provider_options: {}, generation_options: {},
                   authorization: nil, telemetry: nil,
                   request_context: {})
      @client = client || Prescient.client(provider, enable_fallback: true, provider_options: provider_options)
      configured_tools = tools || tool_names.to_h { |name| [name, Prescient.tool(name)] }
      configured_tools = configured_tools.compact
      @registry = ToolRegistry.new(configured_tools)
      @configuration = configuration
      @system_prompt = system_prompt
      @generation_options = generation_options
      @request_context = request_context
      @authorization = authorization || configuration.authorization
      @telemetry = telemetry || configuration.telemetry
      @actions = []
    end

    def run(task)
      validate_task(task)
      context = build_context(task)

      @configuration.max_loops.times do |index|
        emit(:iteration, loop: index + 1)
        response = @client.generate_response(task, context.to_a, **@generation_options)
        unless action_appended?(context, response)
          emit(:completed, loops_run: index + 1, actions: @actions.dup, success: true)
          return result(response, index + 1)
        end
      end

      emit(:max_loops_exceeded, loops_run: @configuration.max_loops, actions: @actions.dup, success: false)
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

      observation = invoke_tool(action)
      @actions << action[:name].to_s
      observation_text = JSON.generate(observation).byteslice(0, @configuration.max_observation_bytes)
      context.append(role: 'assistant', content: response[:response])
      context.append(role: 'user', content: "Observation: #{observation_text}")
      true
    end

    def invoke_tool(action)
      authorize_tool!(action)
      @registry.invoke(action[:name], action[:arguments])
    rescue Prescient::Error => e
      raise if e.is_a?(Prescient::Agent::Error)

      ErrorSerializer.serialize(e)
    end

    def authorize_tool!(action)
      return unless @authorization
      return if @authorization.call(
        tool:      action[:name],
        arguments: action[:arguments].dup,
        context:   @request_context.dup,
      ) == true

      raise UnauthorizedToolError, "agent tool not authorized: #{action[:name]}"
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
        metadata:  { actions: @actions.dup, success: true },
      )
    end

    def emit(event, attributes)
      return unless @telemetry

      @telemetry.call({ event:, **attributes }.freeze)
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
