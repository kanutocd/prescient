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

    missing_prompt = @server.call_tool("prescient_generate")

    assert_includes missing_prompt[:content].first[:text], "invalid_request"
    non_object = @server.call_tool("prescient_generate", [])

    assert_includes non_object[:content].first[:text], "invalid_request"

    authorized = Prescient::MCP::Server.new(
      client_factory: ->(_provider) { Client.new },
      authorization: ->(**) { true }
    )

    assert_includes authorized.call_tool("prescient_providers")[:content].first[:text], "mcp_test"
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

  def test_rack_transport_requires_authentication_and_dispatches_requests
    rack = Prescient::MCP::Rack.new(
      authentication: ->(_env) { { principal: "user-1" } },
      server: @server,
      request_context: ->(env) { { tenant_id: env["HTTP_X_TENANT_ID"] } }
    )
    env = {
      "REQUEST_METHOD" => "POST",
      "HTTP_X_TENANT_ID" => "tenant-1",
      "rack.input" => StringIO.new(JSON.generate(jsonrpc: "2.0", id: 1, method: "initialize"))
    }

    response = rack.call(env)

    assert_equal 200, response.first
    assert_includes JSON.parse(response.last.first).keys, "result"
    session_id = response[1].fetch("mcp-session-id")

    assert_equal 400, rack.call("REQUEST_METHOD" => "GET").first
    next_env = {
      "REQUEST_METHOD" => "POST",
      "HTTP_MCP_SESSION_ID" => session_id,
      "HTTP_MCP_PROTOCOL_VERSION" => Prescient::MCP::Rack::PROTOCOL_VERSION,
      "HTTP_ACCEPT" => "application/json, text/event-stream",
      "rack.input" => StringIO.new(JSON.generate(jsonrpc: "2.0", id: 2, method: "tools/list"))
    }

    assert_equal 200, rack.call(next_env).first

    notification = next_env.merge(
      "rack.input" => StringIO.new(JSON.generate(jsonrpc: "2.0", method: "notifications/initialized"))
    )
    notification_response = rack.call(notification)

    assert_equal 202, notification_response.first
    assert_empty notification_response.last

    sse = next_env.merge(
      "HTTP_ACCEPT" => "text/event-stream",
      "rack.input" => StringIO.new(JSON.generate(jsonrpc: "2.0", id: 3, method: "tools/list"))
    )
    sse_response = rack.call(sse)

    assert_equal 200, sse_response.first
    assert_equal "text/event-stream", sse_response[1]["content-type"]
    assert JSON.parse(sse_response.last.first.delete_prefix("data: ").strip)["result"]

    get_response = rack.call(
      "REQUEST_METHOD" => "GET", "HTTP_MCP_SESSION_ID" => session_id,
      "HTTP_MCP_PROTOCOL_VERSION" => Prescient::MCP::Rack::PROTOCOL_VERSION,
      "HTTP_ACCEPT" => "text/event-stream"
    )

    assert_equal 200, get_response.first
    assert_equal get_response.last.first.bytesize.to_s, get_response[1]["content-length"]

    delete_response = rack.call(
      "REQUEST_METHOD" => "DELETE", "HTTP_MCP_SESSION_ID" => session_id,
      "HTTP_MCP_PROTOCOL_VERSION" => Prescient::MCP::Rack::PROTOCOL_VERSION
    )

    assert_equal 204, delete_response.first
    expired_env = next_env.merge(
      "rack.input" => StringIO.new(JSON.generate(jsonrpc: "2.0", id: 4, method: "tools/list"))
    )

    assert_equal 404, rack.call(expired_env).first

    denied = Prescient::MCP::Rack.new(authentication: ->(_env) { false }, server: @server)

    assert_equal 401, denied.call(env).first
    invalid = env.merge("rack.input" => StringIO.new("{"))

    assert_equal 400, rack.call(invalid).first
    limited = Prescient::MCP::Rack.new(authentication: ->(_env) { true }, max_body_bytes: 2, server: @server)
    limited_env = env.merge("rack.input" => StringIO.new(JSON.generate(jsonrpc: "2.0")))

    assert_equal 400, limited.call(limited_env).first

    invalid_context = Prescient::MCP::Rack.new(
      authentication: ->(_env) { true },
      request_context: ->(_env) { Object.new },
      server: @server
    )
    valid_env = {
      "REQUEST_METHOD" => "POST",
      "rack.input" => StringIO.new(JSON.generate(jsonrpc: "2.0", id: 2, method: "initialize"))
    }

    assert_equal 400, invalid_context.call(valid_env).first
    assert_raises(ArgumentError) do
      Prescient::MCP::Rack.new(authentication: ->(_env) { true }, max_body_bytes: 0, server: @server)
    end
  end

  def test_rack_bearer_authentication_and_origin_policy
    principal = { id: "admin" }
    rack = Prescient::MCP::Rack.new(
      authentication: Prescient::MCP::Authentication::BearerToken.new(token: "secret", principal:),
      server: @server,
      allowed_origins: ["https://app.example"]
    )
    request = JSON.generate(jsonrpc: "2.0", id: 1, method: "initialize")
    base = { "REQUEST_METHOD" => "POST", "rack.input" => StringIO.new(request) }

    assert_equal 401, rack.call(base).first
    assert_equal 403, rack.call(base.merge("HTTP_ORIGIN" => "https://evil.example")).first
    authorized = rack.call(
      base.merge(
        "HTTP_ORIGIN" => "https://app.example", "HTTP_AUTHORIZATION" => "Bearer secret"
      )
    )

    assert_equal 200, authorized.first
    default_principal = Prescient::MCP::Authentication::BearerToken.new(token: "secret")

    assert_equal({ type: "bearer" }, default_principal.call("HTTP_AUTHORIZATION" => "Bearer secret"))
    refute default_principal.call("HTTP_AUTHORIZATION" => "Basic secret")
    refute default_principal.call("HTTP_AUTHORIZATION" => "Bearer wrong")
  end

  def test_rack_enforces_protocol_and_session_rules
    rack = Prescient::MCP::Rack.new(
      authentication: ->(env) { { principal: env["HTTP_X_PRINCIPAL"] || "one" } }, server: @server
    )
    request = lambda do |payload, headers = {}|
      rack.call(
        {
          "REQUEST_METHOD" => "POST",
          "rack.input" => StringIO.new(JSON.generate(payload))
        }.merge(headers)
      )
    end

    assert_equal 405, rack.call("REQUEST_METHOD" => "PUT").first
    assert_equal 400, request.call(jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "old" }).first
    initialized = request.call(jsonrpc: "2.0", id: 1, method: "initialize")
    session_id = initialized[1].fetch("mcp-session-id")
    session_headers = { "HTTP_MCP_SESSION_ID" => session_id }

    assert_equal 400, request.call({ jsonrpc: "2.0", id: 2, method: "tools/list" }, session_headers).first
    mismatch = request.call(
      { jsonrpc: "2.0", id: 2, method: "tools/list" },
      session_headers.merge("HTTP_X_PRINCIPAL" => "two",
                            "HTTP_MCP_PROTOCOL_VERSION" => Prescient::MCP::Rack::PROTOCOL_VERSION)
    )

    assert_equal 401, mismatch.first
    assert_equal 400, request.call(
      { jsonrpc: "2.0", id: 2, method: "tools/list" },
      session_headers.merge("HTTP_MCP_PROTOCOL_VERSION" => "wrong")
    ).first
    assert_equal 400, request.call(
      { jsonrpc: "2.0" },
      session_headers.merge("HTTP_MCP_PROTOCOL_VERSION" => Prescient::MCP::Rack::PROTOCOL_VERSION)
    ).first
    assert_equal 400, request.call({ jsonrpc: "2.0", id: 2, method: "initialize" }, session_headers).first
    assert_equal 400, rack.call(
      "REQUEST_METHOD" => "POST", "rack.input" => StringIO.new("not an object")
    ).first
    assert_equal 400, request.call({ jsonrpc: "1.0", id: 2, method: "tools/list" }, session_headers).first
    assert_equal 400, request.call({ jsonrpc: "2.0", id: 2, method: 42 }, session_headers).first

    no_sse = rack.call(
      "REQUEST_METHOD" => "GET", "HTTP_MCP_SESSION_ID" => session_id,
      "HTTP_MCP_PROTOCOL_VERSION" => Prescient::MCP::Rack::PROTOCOL_VERSION
    )

    assert_equal 400, no_sse.first
  end
end
