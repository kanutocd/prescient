# frozen_string_literal: true

require "test_helper"
require "prescient/agent"
require "prescient/mcp"

class MCPTest < PrescientTest
  class Provider < Prescient::Base
    def generate_embedding(_text, **_options)
      [0.1, 0.2]
    end

    def generate_response(_prompt, _context = [], **_options)
      { response: "generated", provider: "mcp-test", model: "test-model" }
    end

    def health_check
      { status: "healthy", reachable: true, ready: true }
    end

    protected

    def validate_configuration!
      # No validation needed for this test provider.
    end
  end

  class Client
    attr_reader :provider_name

    def initialize
      @provider_name = :mcp_test
    end

    def generate_response(_prompt, _context = [], **_options)
      { response: "generated", provider: "mcp-test", model: "test-model" }
    end

    def generate_embedding(_input, **_options)
      [0.1, 0.2]
    end
  end

  def setup
    super
    Prescient.configure do |config|
      config.default_provider = :mcp_test
      config.add_provider(:mcp_test, Provider)
    end
    @server = Prescient::MCP::Server.new(client_factory: ->(_provider) { Client.new })
  end

  def test_configuration_rejects_invalid_limits_and_server_discovers_capabilities
    assert_raises(ArgumentError) do
      Prescient::MCP::Configuration.new(max_input_bytes: 0)
    end
    assert_equal "prescient", Prescient::MCP::Configuration.new.name
    assert_equal "prescient", @server.initialize_result[:serverInfo][:name]
    assert_equal 5, @server.tools.length
    assert_equal 2, @server.resources.length
    assert_equal "safe", Prescient::Agent::ErrorSerializer.serialize(Prescient::Agent::Error.new("safe"))[:error][:message]

    custom = Prescient::MCP::Server.new(
      configuration: Prescient::MCP::Configuration.new(resources: ["prescient://missing"])
    )

    assert_empty custom.resources
  end

  def test_server_calls_core_tools_and_reads_resources
    generated = @server.call_tool("prescient_generate", { "prompt" => "hello" })

    refute generated[:isError]
    assert_includes generated[:content].first[:text], "generated"

    embedded = @server.call_tool("prescient_embed", { "input" => "hello", "model" => "embed" })

    assert_includes embedded[:content].first[:text], "dimensions"

    assert_includes @server.call_tool("prescient_providers")[:content].first[:text], "mcp_test"
    assert_includes @server.call_tool("prescient_health")[:content].first[:text], "healthy"
    assert_includes @server.call_tool("prescient_health", { "provider" => "mcp_test" })[:content].first[:text], "healthy"
    assert_includes @server.call_tool("prescient_generate", { "prompt" => "hello", "provider" => "mcp_test" })[:content].first[:text], "generated"
    assert_includes @server.read_resource("prescient://providers")[:contents].first[:text], "mcp_test"
    assert_includes @server.read_resource("prescient://health")[:contents].first[:text], "healthy"
  end

  def test_server_enforces_authorization_and_input_limits
    authorization = ->(**) { false }
    denied = Prescient::MCP::Server.new(
      client_factory: ->(_provider) { Client.new },
      authorization:
    ).call_tool("prescient_providers")

    assert denied[:isError]
    assert_includes denied[:content].first[:text], "internal_error"

    limited = Prescient::MCP::Server.new(
      configuration: Prescient::MCP::Configuration.new(max_input_bytes: 5)
    )
    oversized = limited.call_tool("prescient_generate", { "prompt" => "hello" })

    assert_includes oversized[:content].first[:text], "invalid_request"
    assert_raises(ArgumentError) do
      @server.read_resource("prescient://missing")
    end

    disabled = Prescient::MCP::Server.new(configuration: Prescient::MCP::Configuration.new(tools: []))
    disabled_result = disabled.call_tool("prescient_generate", { "prompt" => "hello" })

    assert_includes disabled_result[:content].first[:text], "invalid_request"

    unknown = Prescient::MCP::Server.new(
      configuration: Prescient::MCP::Configuration.new(tools: ["unknown"])
    ).call_tool("unknown")

    assert_includes unknown[:content].first[:text], "invalid_request"
  end

  def test_server_runs_agent_tool_and_stdio_handles_protocol_messages
    agent = @server.call_tool("prescient_agent", { "prompt" => "task", "tools" => [] }, context: { tenant_id: "t1" })

    assert_includes agent[:content].first[:text], "generated"

    requests = [
      { jsonrpc: "2.0", id: 1, method: "initialize" },
      { jsonrpc: "2.0", id: 2, method: "tools/list" },
      { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "prescient_providers" } },
      { jsonrpc: "2.0", id: 4, method: "resources/list" },
      { jsonrpc: "2.0", id: 5, method: "resources/read", params: { uri: "prescient://providers" } },
      { jsonrpc: "2.0", id: 6, method: "unknown" }
    ]
    input = StringIO.new("#{requests.map { |request| JSON.generate(request) }.join("\n")}\ninvalid\n")
    output = StringIO.new
    Prescient::MCP::Stdio.new(server: @server, input:, output:).run
    responses = output.string.lines.map { |line| JSON.parse(line) }

    assert_equal "2.0", responses.first["jsonrpc"]
    assert_equal(-32_601, responses[-2].dig("error", "code"))
    assert_equal(-32_700, responses.last.dig("error", "code"))
  end
end
