# frozen_string_literal: true

require "json"
require "monitor"
require "securerandom"
require "stringio"

# rubocop:disable Style/ClassAndModuleChildren
module Prescient::MCP
  # Optional Rack-compatible MCP HTTP handler with explicit authentication.
  # rubocop:disable Metrics/ClassLength
  class Rack
    # MCP protocol version supported by the HTTP transport.
    # @return [String] Protocol version identifier
    PROTOCOL_VERSION = "2025-06-18"
    # Rack environment key containing the MCP session identifier.
    # @return [String] Rack header key
    SESSION_HEADER = "HTTP_MCP_SESSION_ID"
    # Rack environment key containing the MCP protocol version.
    # @return [String] Rack header key
    PROTOCOL_HEADER = "HTTP_MCP_PROTOCOL_VERSION"
    # Default policy allowing requests without an Origin header restriction.
    # @return [Array<String>] Empty Origin allowlist
    ALLOWED_ORIGINS_DEFAULT = [].freeze

    def initialize(authentication:, server: Server.new, request_context: nil,
                   max_body_bytes: Configuration::DEFAULT_MAX_INPUT_BYTES,
                   allowed_origins: ALLOWED_ORIGINS_DEFAULT, session_ttl: 3600)
      @server = server
      @authentication = authentication
      @request_context = request_context
      @max_body_bytes = validate_limit(max_body_bytes)
      @allowed_origins = Array(allowed_origins).map(&:to_s).freeze
      @session_ttl = validate_session_ttl(session_ttl)
      @sessions = {}
      @sessions_lock = Monitor.new
    end

    # Handle one MCP Streamable HTTP request.
    # @param env [Hash] Rack environment
    # @return [Array] Rack response
    def call(env)
      method = env.fetch("REQUEST_METHOD", "GET").upcase
      unless %w[POST GET DELETE].include?(method)
        return response(
          405, { error: "method_not_allowed" }, { "allow" => "POST, GET, DELETE" }
        )
      end
      return response(403, { error: "origin_not_allowed" }) unless origin_allowed?(env)

      authentication = authenticate(env)
      unless authentication
        return response(401, { error: "authentication_required" }, { "www-authenticate" => "Bearer" })
      end

      return post(env, authentication) if method == "POST"
      return get(env, authentication) if method == "GET"

      delete(env, authentication)
    rescue JSON::ParserError
      response(400, { error: "invalid_json" })
    rescue SessionNotFoundError
      response(404, { error: "session_not_found" })
    rescue AuthenticationError
      response(401, { error: "authentication_failed" })
    rescue ArgumentError
      response(400, { error: "invalid_request" })
    rescue StandardError
      response(500, { error: "internal_error" })
    end

    private

    def post(env, authentication)
      request = parse_request(env)
      initialize_request = request["method"] == "initialize"
      session_id = env[SESSION_HEADER]
      if initialize_request
        raise ArgumentError, "initialize must not include a session" if session_id

        validate_protocol!(request)
        result = @server.dispatch(request, context: request_context(env, authentication))
        session_id = new_session(authentication)
        return response_for(request, result, 200, headers: { "mcp-session-id" => session_id })
      end

      session = session_for(session_id)
      validate_session!(session, authentication)
      validate_protocol_header!(env)
      result = @server.dispatch(request, context: request_context(env, authentication))
      return response(202, nil) if notification?(request)

      response_for(request, result, 200, sse: accepts_sse?(env))
    end

    def parse_request(env)
      body = env.fetch("rack.input", StringIO.new).read(@max_body_bytes + 1)
      raise ArgumentError, "request body exceeds configured limit" if body.bytesize > @max_body_bytes

      request = JSON.parse(body)
      raise ArgumentError, "request must be an object" unless request.is_a?(Hash)
      raise ArgumentError, "request must be JSON-RPC 2.0" unless request["jsonrpc"] == "2.0"
      raise ArgumentError, "request method must be a string" unless request["method"].is_a?(String)

      request
    end

    def get(env, authentication)
      session = session_for(env[SESSION_HEADER])
      validate_session!(session, authentication)
      validate_protocol_header!(env)
      raise ArgumentError, "GET requires text/event-stream" unless accepts_sse?(env)

      response(200, nil, { "content-type" => "text/event-stream", "cache-control" => "no-cache",
                           "x-accel-buffering" => "no" }, body: ": keep-alive\n\n")
    end

    def delete(env, authentication)
      session_id = env[SESSION_HEADER]
      session = session_for(session_id)
      validate_session!(session, authentication)
      validate_protocol_header!(env)
      @sessions_lock.synchronize { @sessions.delete(session_id) }
      [204, {}, []]
    end

    def authenticate(env)
      result = @authentication.call(env)
      result == false || result.nil? ? nil : result
    end

    def origin_allowed?(env)
      origin = env["HTTP_ORIGIN"]
      origin.nil? || @allowed_origins.include?(origin)
    end

    def new_session(authentication)
      session_id = SecureRandom.uuid
      expires_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @session_ttl
      @sessions_lock.synchronize do
        prune_expired_sessions
        @sessions[session_id] = { authentication: authentication, expires_at: expires_at }
      end
      session_id
    end

    def session_for(session_id)
      raise ArgumentError, "MCP session is required" if session_id.to_s.empty?

      session = @sessions_lock.synchronize do
        prune_expired_sessions
        @sessions[session_id]
      end
      raise SessionNotFoundError unless session

      session
    end

    def validate_session!(session, authentication)
      return if session[:authentication] == authentication

      raise AuthenticationError
    end

    def validate_protocol!(request)
      version = request.dig("params", "protocolVersion")
      return if version.nil? || version == PROTOCOL_VERSION

      raise ArgumentError, "unsupported MCP protocol version"
    end

    def validate_protocol_header!(env)
      return if env[PROTOCOL_HEADER].to_s == PROTOCOL_VERSION

      raise ArgumentError, "MCP protocol version header is required"
    end

    def notification?(request)
      !request.key?("id")
    end

    def accepts_sse?(env)
      env.fetch("HTTP_ACCEPT", "").split(",").map(&:strip).include?("text/event-stream")
    end

    def response_for(request, result, status, sse: false, headers: {})
      payload = { jsonrpc: "2.0", id: request["id"], result: }
      if sse
        body = "data: #{JSON.generate(payload)}\n\n"
        sse_headers = headers.merge("content-type" => "text/event-stream", "cache-control" => "no-cache")
        return response(status, nil, sse_headers, body:)
      end

      response(status, payload, headers)
    end

    def request_context(env, authentication)
      base = {
        request_id: SecureRandom.uuid,
        tenant_id: env["HTTP_X_TENANT_ID"],
        principal: authentication == true ? env["REMOTE_USER"] : authentication
      }.compact
      return base unless @request_context

      context = @request_context.call(env)
      raise ArgumentError, "request context hook must return a mapping" unless context.is_a?(Hash)

      base.merge(context)
    end

    def response(status, payload, headers = {}, body: nil)
      body ||= payload.nil? ? "" : JSON.generate(payload)
      response_headers = { "content-type" => "application/json", "content-length" => body.bytesize.to_s }
      [status, response_headers.merge(headers), body.empty? ? [] : [body]]
    end

    def validate_limit(value)
      return value if value.is_a?(Integer) && value.positive?

      raise ArgumentError, "max_body_bytes must be a positive integer"
    end

    def validate_session_ttl(value)
      return value if value.is_a?(Numeric) && value.positive?

      raise ArgumentError, "session_ttl must be a positive number"
    end

    def prune_expired_sessions
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @sessions.delete_if { |_id, session| session[:expires_at] <= now }
    end
  end
  # rubocop:enable Metrics/ClassLength

  class SessionNotFoundError < StandardError
  end

  # Raised when an authenticated request does not own the MCP session.
  class AuthenticationError < StandardError
  end
end
# rubocop:enable Style/ClassAndModuleChildren
