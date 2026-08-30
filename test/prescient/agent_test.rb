# frozen_string_literal: true

require "test_helper"
require "prescient/agent"

class AgentTest < PrescientTest
  class FakeTool
    def search(query, limit: nil)
      { query: query, limit: limit, result: "found" }
    end
  end

  class FailingTool
    def search(_query, **)
      raise Prescient::ToolError, "provider body: secret response payload"
    end
  end

  class CallableTool
    attr_reader :description, :schema

    def initialize
      @description = "Return an account summary."
      @schema = { type: "object", required: ["account_id"] }
    end

    def call(arguments)
      { account_id: arguments["account_id"], status: "due" }
    end
  end

  class BareCallableTool
    def call(_arguments)
      { result: "ok" }
    end
  end

  class FakeClient
    attr_reader :calls, :provider_name

    def initialize(responses)
      @responses = responses
      @calls = []
      @provider_name = :fake
    end

    def generate_response(prompt, context = [])
      @calls << { prompt: prompt, context: context }
      @responses.fetch(@calls.length - 1)
    end
  end

  def test_returns_final_response_without_tool_call
    client = FakeClient.new([{ response: "done", provider: "fake", model: "model" }])
    result = Prescient::Agent::Runtime.new(client:, tools: {}).run("task")

    assert_predicate result, :success?
    assert_equal "done", result.response
    assert_equal 1, result.loops_run
  end

  def test_executes_one_allowed_tool_and_feeds_observation_back
    client = FakeClient.new(
      [
        { response: "Thought\n```json\n{\"action\":\"search\",\"args\":{\"query\":\"Ruby\",\"limit\":1}}\n```" },
        { response: "final", provider: "fake", model: "model" }
      ]
    )
    runtime = Prescient::Agent::Runtime.new(client:, tools: { search: FakeTool.new })

    result = runtime.run("find Ruby")

    assert_equal "final", result.response
    assert_equal 2, result.loops_run
    assert_includes client.calls.last[:context].last[:content], "Ruby"
  end

  def test_serializes_tool_failures_without_exposing_provider_details
    client = FakeClient.new(
      [
        { response: "```json\n{\"action\":\"search\",\"args\":{\"query\":\"Ruby\"}}\n```" },
        { response: "final" }
      ]
    )

    Prescient::Agent::Runtime.new(client:, tools: { search: FailingTool.new }).run("find Ruby")

    observation = client.calls.last[:context].last[:content]

    assert_includes observation, "tool_failure"
    refute_includes observation, "secret response payload"
  end

  def test_rejects_unallowed_tool
    client = FakeClient.new([{ response: "```json\n{\"action\":\"unknown\",\"args\":{}}\n```" }])

    assert_raises(Prescient::Agent::UnauthorizedToolError) do
      Prescient::Agent::Runtime.new(client:, tools: {}).run("task")
    end
  end

  def test_invokes_generic_callable_tools
    client = FakeClient.new(
      [
        { response: "```json\n{\"action\":\"accounts\",\"args\":{\"account_id\":\"acct-1\"}}\n```" },
        { response: "account is due" }
      ]
    )

    result = Prescient::Agent::Runtime.new(client:, tools: { accounts: CallableTool.new }).run("check account")

    assert_equal "account is due", result.response
    assert_equal ["accounts"], result.metadata[:actions]
    assert_includes client.calls.last[:context].last[:content], "acct-1"
  end

  def test_authorization_and_telemetry_receive_request_scoped_data
    events = []
    client = FakeClient.new(
      [
        { response: "```json\n{\"action\":\"accounts\",\"args\":{\"account_id\":\"acct-1\"}}\n```" },
        { response: "done" }
      ]
    )
    authorization = lambda { |tool:, arguments:, context:|
      tool == :accounts && arguments["account_id"] == "acct-1" && context[:tenant_id] == "tenant-1"
    }
    configuration = Prescient::Agent::Configuration.new(authorization:, telemetry: ->(event) { events << event })

    result = Prescient::Agent::Runtime.new(
      client:, tools: { accounts: CallableTool.new }, configuration:, request_context: { tenant_id: "tenant-1" }
    ).run("task")

    assert_predicate result, :success?
    assert_equal :completed, events.last[:event]
    assert events.last[:success]
    assert(events.all? { |event| !event.key?(:prompt) })
  end

  def test_rejects_non_callable_policy_and_unauthorized_actions
    assert_raises(Prescient::Agent::ConfigurationError) do
      Prescient::Agent::Configuration.new(authorization: Object.new)
    end

    client = FakeClient.new(
      [{ response: "```json\n{\"action\":\"accounts\",\"args\":{\"account_id\":\"acct-1\"}}\n```" }]
    )
    configuration = Prescient::Agent::Configuration.new(authorization: ->(**) { false })

    assert_raises(Prescient::Agent::UnauthorizedToolError) do
      Prescient::Agent::Runtime.new(
        client:, tools: { accounts: CallableTool.new }, configuration:
      ).run("task")
    end
    assert_raises(Prescient::Agent::ConfigurationError) do
      Prescient::Agent::Runtime.new(client:, tools: {}).run(nil)
    end
  end

  def test_rejects_malformed_action
    client = FakeClient.new([{ response: "```json\n{\"action\":\"search\"}\n```" }])

    assert_raises(Prescient::Agent::MalformedActionError) do
      Prescient::Agent::Runtime.new(client:, tools: { search: FakeTool.new }).run("task")
    end
  end

  def test_stops_at_maximum_loops
    action = { response: "```json\n{\"action\":\"search\",\"args\":{\"query\":\"Ruby\"}}\n```" }
    client = FakeClient.new([action, action])
    configuration = Prescient::Agent::Configuration.new(max_loops: 2)

    assert_raises(Prescient::Agent::MaxLoopsExceededError) do
      Prescient::Agent::Runtime.new(
        client:, tools: { search: FakeTool.new }, configuration:
      ).run("task")
    end
  end

  def test_prescient_does_not_load_agent_implementation_by_default
    output = run_ruby(<<~RUBY)
      require 'prescient'
      abort 'agent implementation loaded' if $LOADED_FEATURES.any? { |path| path.end_with?('/prescient/agent/runtime.rb') }
      abort 'agent autoload missing' unless Prescient.autoload?(:Agent)
    RUBY

    assert_empty output
  end

  def test_configuration_rejects_invalid_limits
    assert_raises(Prescient::Agent::ConfigurationError) do
      Prescient::Agent::Configuration.new(max_loops: 0)
    end
    assert_raises(Prescient::Agent::ConfigurationError) do
      Prescient::Agent::Configuration.new(max_context_bytes: -1)
    end
    assert_raises(Prescient::Agent::ConfigurationError) do
      Prescient::Agent::Configuration.new(max_action_bytes: "large")
    end
    assert_raises(Prescient::Agent::ConfigurationError) do
      Prescient::Agent::Configuration.new(max_observation_bytes: nil)
    end
    assert_raises(Prescient::Agent::ConfigurationError) do
      Prescient::Agent::Configuration.new(max_task_bytes: 0)
    end
    assert_raises(Prescient::Agent::ConfigurationError) do
      Prescient::Agent::Configuration.new(max_response_bytes: "large")
    end
  end

  def test_context_rejects_initial_and_appended_overflow
    assert_raises(Prescient::Agent::ConfigurationError) do
      Prescient::Agent::Context.new(system_prompt: "x", task: "y", max_bytes: 1)
    end

    context = Prescient::Agent::Context.new(system_prompt: "x", task: "y", max_bytes: 100)
    assert_raises(Prescient::Agent::ConfigurationError) do
      context.append(role: "user", content: "x" * 200)
    end
  end

  def test_context_compacts_older_turns_with_an_omission_marker
    context = Prescient::Agent::Context.new(system_prompt: "system", task: "task", max_bytes: 500)
    3.times do |index|
      context.append(role: "assistant", content: "action #{index} #{"x" * 50}")
      context.append(role: "user", content: "observation #{index} #{"y" * 50}")
    end

    assert_operator JSON.generate(context.to_a).bytesize, :<=, 500
    assert_includes context.messages.map { |message| message[:content] },
                    "[Earlier agent context omitted due to size limit.]"
    assert_includes context.messages.last[:content], "observation 2"
  end

  def test_error_serializer_uses_safe_messages_for_core_errors
    serialized = Prescient::Agent::ErrorSerializer.serialize(
      Prescient::ConnectionError.new("raw provider body: secret")
    )

    assert_equal "provider_unavailable", serialized[:error][:category]
    assert_equal "The requested operation failed.", serialized[:error][:message]
    refute_includes JSON.generate(serialized), "secret"
  end

  def test_runtime_enforces_task_and_response_limits_and_emits_failures
    client = FakeClient.new([{ response: "x" * 20 }])
    configuration = Prescient::Agent::Configuration.new(max_task_bytes: 2, max_response_bytes: 2)

    assert_raises(Prescient::Agent::ConfigurationError) do
      Prescient::Agent::Runtime.new(client:, tools: {}, configuration:).run("task")
    end

    events = []
    configuration = Prescient::Agent::Configuration.new(max_response_bytes: 2, telemetry: ->(event) { events << event })
    assert_raises(Prescient::Agent::ConfigurationError) do
      Prescient::Agent::Runtime.new(client:, tools: {}, configuration:).run("ok")
    end
    assert_equal :failed, events.last[:event]
    refute events.last[:success]
  end

  def test_reusing_runtime_does_not_leak_state_between_runs
    client = FakeClient.new(
      [
        { response: "```json\n{\"action\":\"accounts\",\"args\":{\"account_id\":\"acct-1\"}}\n```" },
        { response: "first" },
        { response: "second" }
      ]
    )
    runtime = Prescient::Agent::Runtime.new(client:, tools: { accounts: CallableTool.new })

    first = runtime.run("check account")
    second = runtime.run("check another account")

    assert_equal ["accounts"], first.metadata[:actions]
    assert_empty second.metadata[:actions]
    assert_equal 1, second.loops_run
  end

  def test_tool_schema_validates_required_and_additional_arguments
    tool = CallableTool.new
    tool.instance_variable_set(
      :@schema,
      {
        type: "object", required: ["account_id"], properties: { account_id: { type: "string" } },
        additionalProperties: false
      }
    )
    registry = Prescient::Agent::ToolRegistry.new(accounts: tool)

    assert_raises(Prescient::Agent::MalformedActionError) { registry.invoke(:accounts, {}) }
    assert_raises(Prescient::Agent::MalformedActionError) do
      registry.invoke(:accounts, { account_id: "acct-1", extra: true })
    end
    assert_equal({ account_id: "acct-1", status: "due" }, registry.invoke(:accounts, { "account_id" => "acct-1" }))
    assert_equal({}, Prescient::Agent::SchemaValidator.validate!({}, {}))
    assert_raises(Prescient::Agent::MalformedActionError) do
      Prescient::Agent::SchemaValidator.validate!({ type: "boolean" }, "true")
    end
  end

  def test_parser_returns_nil_without_an_action_and_rejects_oversize_actions
    assert_nil Prescient::Agent::Parser.parse("final answer")
    action = "```json\n{\"action\":\"search\",\"args\":{\"query\":\"Ruby\"}}\n```"

    assert_raises(Prescient::Agent::MalformedActionError) do
      Prescient::Agent::Parser.parse(action, max_bytes: 1)
    end
  end

  def test_parser_rejects_invalid_json_and_invalid_action_arguments
    assert_raises(Prescient::Agent::MalformedActionError) do
      Prescient::Agent::Parser.parse("```json\n{invalid}\n```")
    end
    assert_raises(Prescient::Agent::MalformedActionError) do
      Prescient::Agent::Parser.parse("```json\n{\"action\":\"search\",\"args\":[] }\n```")
    end
  end

  def test_registry_rejects_non_search_tools_and_missing_queries
    assert_raises(Prescient::Agent::ConfigurationError) do
      Prescient::Agent::ToolRegistry.new({ unsupported: Object.new })
    end

    registry = Prescient::Agent::ToolRegistry.new(search: FakeTool.new)
    assert_raises(Prescient::Agent::MalformedActionError) do
      registry.invoke(:search, {})
    end
    assert_raises(Prescient::Agent::MalformedActionError) do
      registry.invoke(:search, { "query" => "" })
    end

    bare = Prescient::Agent::ToolRegistry.new(bare: BareCallableTool.new)

    assert_equal({ result: "ok" }, bare.invoke(:bare, {}))
  end
end
