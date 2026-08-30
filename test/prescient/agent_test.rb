# frozen_string_literal: true

require 'test_helper'
require 'prescient/agent'

class AgentTest < PrescientTest
  class FakeTool
    def search(query, limit: nil)
      { query: query, limit: limit, result: 'found' }
    end
  end

  class FakeClient
    attr_reader :calls
    attr_reader :provider_name

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
    client = FakeClient.new([{ response: 'done', provider: 'fake', model: 'model' }])
    result = Prescient::Agent::Runtime.new(client:, tools: {}).run('task')

    assert_predicate result, :success?
    assert_equal 'done', result.response
    assert_equal 1, result.loops_run
  end

  def test_executes_one_allowed_tool_and_feeds_observation_back
    client = FakeClient.new(
      [
        { response: "Thought\n```json\n{\"action\":\"search\",\"args\":{\"query\":\"Ruby\",\"limit\":1}}\n```" },
        { response: 'final', provider: 'fake', model: 'model' },
      ],
    )
    runtime = Prescient::Agent::Runtime.new(client:, tools: { search: FakeTool.new })

    result = runtime.run('find Ruby')

    assert_equal 'final', result.response
    assert_equal 2, result.loops_run
    assert_includes client.calls.last[:context].last[:content], 'Ruby'
  end

  def test_rejects_unallowed_tool
    client = FakeClient.new([{ response: "```json\n{\"action\":\"unknown\",\"args\":{}}\n```" }])

    assert_raises(Prescient::Agent::UnauthorizedToolError) do
      Prescient::Agent::Runtime.new(client:, tools: {}).run('task')
    end
  end

  def test_rejects_malformed_action
    client = FakeClient.new([{ response: "```json\n{\"action\":\"search\"}\n```" }])

    assert_raises(Prescient::Agent::MalformedActionError) do
      Prescient::Agent::Runtime.new(client:, tools: { search: FakeTool.new }).run('task')
    end
  end

  def test_stops_at_maximum_loops
    action = { response: "```json\n{\"action\":\"search\",\"args\":{\"query\":\"Ruby\"}}\n```" }
    client = FakeClient.new([action, action])
    configuration = Prescient::Agent::Configuration.new(max_loops: 2)

    assert_raises(Prescient::Agent::MaxLoopsExceededError) do
      Prescient::Agent::Runtime.new(
        client:, tools: { search: FakeTool.new }, configuration:,
      ).run('task')
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
      Prescient::Agent::Configuration.new(max_action_bytes: 'large')
    end
    assert_raises(Prescient::Agent::ConfigurationError) do
      Prescient::Agent::Configuration.new(max_observation_bytes: nil)
    end
  end

  def test_context_rejects_initial_and_appended_overflow
    assert_raises(Prescient::Agent::ConfigurationError) do
      Prescient::Agent::Context.new(system_prompt: 'x', task: 'y', max_bytes: 1)
    end

    context = Prescient::Agent::Context.new(system_prompt: 'x', task: 'y', max_bytes: 100)
    assert_raises(Prescient::Agent::ConfigurationError) do
      context.append(role: 'user', content: 'x' * 200)
    end
  end

  def test_parser_returns_nil_without_an_action_and_rejects_oversize_actions
    assert_nil Prescient::Agent::Parser.parse('final answer')
    action = "```json\n{\"action\":\"search\",\"args\":{\"query\":\"Ruby\"}}\n```"

    assert_raises(Prescient::Agent::MalformedActionError) do
      Prescient::Agent::Parser.parse(action, max_bytes: 1)
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
      registry.invoke(:search, { 'query' => '' })
    end
  end
end
