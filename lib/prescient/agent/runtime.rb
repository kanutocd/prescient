# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::Agent
  # Runs a bounded single-agent tool-calling loop through Prescient::Client.
  class Runtime
    def initialize(provider: nil, client: nil, tools: nil, tool_names: [], configuration: Configuration.new,
                   system_prompt: "You are a helpful assistant.", provider_options: {}, generation_options: {},
                   authorization: nil, telemetry: nil, enable_fallback: true,
                   request_context: {})
      @configuration = configuration
      @telemetry = telemetry || configuration.telemetry
      @authorization = authorization || configuration.authorization
      @request_context = request_context
      @system_prompt = system_prompt
      @generation_options = generation_options

      begin
        @client = client || Prescient.client(provider, enable_fallback:, provider_options:)
        configured_tools = tools || tool_names.to_h { |name| [name, Prescient.tool(name)] }
        @registry = ToolRegistry.new(configured_tools.compact)
      rescue StandardError => e
        emit_failure(e, phase: :initialization, loops_run: 0, actions: [])
        raise
      end
    end

    # Execute one bounded agent task.
    # @param task [String] Task instruction
    # @return [Result] Completed agent result
    def run(task)
      actions = []
      loops_run = 0
      validate_task(task)
      context = build_context(task)

      @configuration.max_loops.times do |index|
        loops_run = index + 1
        emit(:iteration, loop: index + 1)
        response = @client.generate_response(task, context.to_a, **@generation_options)
        validate_response!(response)
        unless action_appended?(context, response, actions)
          emit(:completed, loops_run: index + 1, actions: actions.dup, success: true)
          return result(response, index + 1, actions)
        end
      end

      emit(:max_loops_exceeded, loops_run: @configuration.max_loops, actions: actions.dup, success: false)
      raise MaxLoopsExceededError, "agent exceeded maximum loops: #{@configuration.max_loops}"
    rescue StandardError => e
      emit_failure(e, phase: :execution, loops_run:, actions: actions.dup)
      raise
    end

    private

    def build_context(task)
      Context.new(
        system_prompt: PromptBuilder.build(system_instruction: @system_prompt, tools: @registry.all),
        task: task,
        max_bytes: @configuration.max_context_bytes
      )
    end

    def action_appended?(context, response, actions)
      action = Parser.parse(response[:response], max_bytes: @configuration.max_action_bytes)
      return false unless action

      observation = invoke_tool(action)
      actions << action[:name].to_s
      observation_text = bounded_observation(observation)
      context.append(role: "assistant", content: response[:response])
      context.append(role: "user", content: "Observation: #{observation_text}")
      true
    end

    def bounded_observation(observation)
      serialized = JSON.generate(observation)
      return serialized if serialized.bytesize <= @configuration.max_observation_bytes

      limit = @configuration.max_observation_bytes
      envelope = lambda do |value|
        JSON.generate(truncated: true, value: value)
      end
      return limit < 4 ? "0" : "null" if limit < envelope.call("").bytesize

      low = 0
      high = serialized.bytesize
      while low < high
        midpoint = (low + high + 1) / 2
        candidate = envelope.call(utf8_prefix(serialized, midpoint))
        if candidate.bytesize <= limit
          low = midpoint
        else
          high = midpoint - 1
        end
      end

      envelope.call(utf8_prefix(serialized, low))
    end

    def utf8_prefix(value, max_bytes)
      value.byteslice(0, max_bytes).to_s.force_encoding(Encoding::UTF_8).scrub
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
        tool: action[:name],
        arguments: action[:arguments].dup,
        context: @request_context.dup
      ) == true

      raise UnauthorizedToolError, "agent tool not authorized: #{action[:name]}"
    end

    def validate_task(task)
      valid = task.is_a?(String) && !task.strip.empty? && task.bytesize <= @configuration.max_task_bytes
      return if valid

      raise ConfigurationError, "agent task must be a non-empty string within #{@configuration.max_task_bytes} bytes"
    end

    def validate_response!(response)
      text = response[:response]
      return if text.is_a?(String) && text.bytesize <= @configuration.max_response_bytes

      raise ConfigurationError,
            "agent response must be a string within #{@configuration.max_response_bytes} bytes"
    end

    def result(response, loops_run, actions)
      Result.new(
        response: response[:response],
        provider: response[:provider] || @client.provider_name,
        model: response[:model],
        loops_run: loops_run,
        metadata: { actions: actions.dup, success: true }
      )
    end

    def emit(event, attributes)
      return unless @telemetry

      @telemetry.call({ event:, **attributes }.freeze)
    rescue StandardError
      nil
    end

    def emit_failure(error, phase:, loops_run:, actions:)
      emit(
        :failed,
        phase:, loops_run:, actions:, success: false,
        error: ErrorSerializer.serialize(error).fetch(:error)
      )
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
